# DB 적재 방식 비교 결과 (동기 vs 비동기)

실험 정의는 [../../sync-vs-async-loading-experiment.md](../../sync-vs-async-loading-experiment.md)를 따른다.

데이터 규모 단계는 `docs/large-db-experiment.md`의 Stage 1~4에 Stage 0(1만
건)을 추가한 것을 그대로 쓴다. Stage 번호는 두 문서에서 항상 같은 배경
데이터 규모를 가리킨다.

| 단계 | COUPON_ISSUE(배경 데이터) |
| --- | ---: |
| Stage 0 | 정확히 10,000 (`seed-stage0-trim.sql`) |
| Stage 1 | 300,000 |
| Stage 2 | 900,000 |
| Stage 3 | 1,500,000 |
| Stage 4 | 3,000,000 |

```text
sync-vs-async/
├── raw/               # run-vu-sweep.sh가 남기는 1초 간격 원본 기록(.tsv) + stage별 k6 로그
├── sync/              # 동기(단건 JdbcTemplate) 적재 결과
│   ├── stage-0.md        VU 10~500, INSERT만 / INSERT+UPDATE
│   ├── stage-1.md        〃 (배경 데이터 30만)
│   ├── stage-2.md        〃 (90만)
│   ├── stage-3.md        〃 (150만)
│   └── stage-4.md        〃 (300만) + Stage 0~4 종합
├── analysis-notes.md  # 왜 이런 결과가 나왔는지 — 스레드/풀 트레이드오프,
│                      # 버퍼 풀·fsync·CPU 원인 분석, 비동기 전환 시 예상되는
│                      # 변화 등 결과 표 뒤의 해석을 상세히 기록
└── async/             # 비동기(배치) 적재 결과 — 구현 후 채움
```

결과 **표**는 각 `sync/stage-N.md`에, **왜 그런 결과가 나왔는지**(스레드·
커넥션 풀 트레이드오프, 버퍼 풀 vs CPU 원인 분석, 비동기 전환 예상 등
결과를 두고 나눈 논의)는 [`analysis-notes.md`](analysis-notes.md)에
정리했다. 이 README는 그 둘의 요약만 담는다.

각 stage 문서에는 INSERT만 / INSERT+UPDATE 두 워크로드를 나란히 기록한다.

- 요청 건수, VU, 소요 시간
- Avg, p95, 오류율, 처리량
- `hikaricp_connections_active`/`pending`, `tomcat_threads_busy` — `collect-pool-metrics.sh` 기록에서 최댓값
- InnoDB 버퍼 풀 캐시 미스율, `Innodb_os_log_fsyncs` 증가량 — 같은 기록에서
- 요청 건수 대비 실제 적재 성공 건수(정합성)

단계를 올릴 때마다(Stage 1, 2 …) 같은 형식으로 문서를 추가하고, 어느
단계·어느 워크로드에서 어떤 지표가 무너졌는지 이 README에 요약을 남긴다.

## 요약 (진행하며 갱신)

VU(동시성)를 10~500까지 올리며 같은 총 요청량(~10,000건)으로, Stage
0~4(배경 데이터 1만~300만 건) 전 구간을 동일 조건으로 측정 완료.
상세 표·분석은 각 stage 문서, 전 구간 종합은
[`sync/stage-4.md`](sync/stage-4.md)의 "Stage 0~4 종합".

| 단계 | 동기 결과 | 비동기 결과 |
| --- | --- | --- |
| Stage 0 (1만) | VU=200 포화, VU=300부터 실패 시작, VU=500에서 급증(INSERT+UPDATE 24.11%, TCP 연결 거부) | 미구현 |
| Stage 1 (30만) | 동일 패턴, VU=500 INSERT+UPDATE 실패 12.80% | 미구현 |
| Stage 2 (90만) | 동일 패턴, VU=500 INSERT+UPDATE 실패 2.65% | 미구현 |
| Stage 3 (150만) | 동일 패턴 + INSERT만에서도 row lock 발생 시작, VU=500 p95 556ms(최고치) | 미구현 |
| Stage 4 (300만) | **VU=10 기준선 자체가 2.5배 느려짐**(8ms→21ms, 동시성과 무관한 별도 병목), 포화·실패 VU 지점은 동일 | 미구현 |

**핵심 발견 3가지**

1. **동시성 breakpoint(VU≈200 포화, VU≈300~500 실패)는 데이터 규모와
   거의 무관하게 일정하다** — Tomcat 스레드(200)·HikariCP 풀(50) 크기로
   정해지는 구조적 한계라서 그렇다.
2. **Stage 4(300만 건)에서 동시성과 무관한 별도 병목이 새로 나타난다**
   — VU=10(사실상 무경합)에서도 응답시간이 3배 가까이 느려졌다. 버퍼
   풀(기본 128MB) 초과가 유력한 원인으로 추정된다.
3. 실패는 애플리케이션 에러가 아니라 OS/Tomcat 레벨의 TCP 연결 거부
   (`connection actively refused`)다. 동기 방식엔 재시도가 없어 거부된
   요청은 그대로 유실 — Stage 0 VU=500 INSERT+UPDATE에서 10,000건 요청
   중 7,589건만 실제 적재됨.
