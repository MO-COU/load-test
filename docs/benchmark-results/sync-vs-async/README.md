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
├── raw/                  # run-vu-sweep(-async).sh가 남기는 1초 간격 원본 기록(.tsv) + stage별 k6 로그
├── sync/                 # 동기(단건 JdbcTemplate) 적재 결과
│   ├── stage-0.md           VU 10~500, INSERT만 / INSERT+UPDATE
│   ├── stage-1.md           〃 (배경 데이터 30만)
│   ├── stage-2.md           〃 (90만)
│   ├── stage-3.md           〃 (150만)
│   └── stage-4.md           〃 (300만) + Stage 0~4 종합
├── async/                # 비동기(배치) 적재 결과
│   ├── stage-0.md           VU 10~500, nobatch(BATCH_SIZE=1) vs batch100 나란히 비교
│   └── stage-1-to-4.md      〃 (배경 데이터 30만~300만) + Stage 0~4 종합
├── full-comparison.md    # 동기·비동기-nobatch·비동기-batch100 전체 데이터를
│                         # Stage×VU×워크로드 단위로 한 표에 모은 비교표
└── analysis-notes.md     # 왜 이런 결과가 나왔는지 — 스레드/풀 트레이드오프,
                          # 버퍼 풀·fsync·CPU 원인 분석, 비동기 전환 시 예상되는
                          # 변화 등 결과 표 뒤의 해석을 상세히 기록
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

VU(동시성)를 10~500까지 올리며 같은 총 요청량(~10,000건)으로, **동기·
비동기 모두 Stage 0~4(배경 데이터 1만~300만 건) 전 구간을 측정
완료했다.** 상세 표·분석은 각 stage 문서, 동기 종합은
[`sync/stage-4.md`](sync/stage-4.md)의 "Stage 0~4 종합", 비동기 종합은
[`async/stage-1-to-4.md`](async/stage-1-to-4.md)의 "Stage 0~4 종합".
**세 조건(동기·비동기-nobatch·비동기-batch100)의 모든 Stage×VU×워크로드
데이터를 한 표씩 나란히 모은 전체 비교표는
[`full-comparison.md`](full-comparison.md)에 있다.**

| 단계 | 동기 결과 | 비동기 결과 |
| --- | --- | --- |
| Stage 0 (1만) | VU=200 포화, VU=300부터 실패 시작, VU=500에서 급증(INSERT+UPDATE 24.11%, TCP 연결 거부) | Tomcat/풀 포화 없음, VU=500 INSERT+UPDATE 실패 0.25~0.49%로 급감. 배치(100) vs 무배치(1) 차이는 응답 지연이 아니라 drain 시간에서 나타남 — batch100은 VU 무관 6~12초로 평평, nobatch는 VU가 오를수록 늘다 60초 컷오프에 막힘(단일 컨슈머 스레드 처리 상한). 상세: [`async/stage-0.md`](async/stage-0.md) |
| Stage 1 (30만) | 동일 패턴, VU=500 INSERT+UPDATE 실패 12.80% | batch100 drain 여전히 6~14초로 평평. nobatch는 VU=10에서도 여전히 ~50초에 겨우 완주(Stage 0과 비슷) |
| Stage 2 (90만) | 동일 패턴, VU=500 INSERT+UPDATE 실패 2.65% | batch100 그대로 평평. **nobatch는 VU=10에서조차 60초 안에 못 비움 — Stage 1→2 사이에서 단일 컨슈머 처리량이 한 단계 더 떨어짐** |
| Stage 3 (150만) | 동일 패턴 + INSERT만에서도 row lock 발생 시작, VU=500 p95 556ms(최고치) | batch100 평평 유지, nobatch 계속 60초 컷오프 |
| Stage 4 (300만) | **VU=10 기준선 자체가 2.5배 느려짐**(8ms→21ms, 동시성과 무관한 별도 병목), 포화·실패 VU 지점은 동일 | **동기에서 본 버퍼 풀 병목이 batch100 drain 시간에는 재현 안 됨**(Stage 0과 동일하게 6~7초) — 원인 미확정. nobatch는 계속 60초 컷오프 |

상세: [`async/stage-0.md`](async/stage-0.md), [`async/stage-1-to-4.md`](async/stage-1-to-4.md).

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
4. **(Stage 0 비동기 측정 후 추가)** 비동기는 "요청 스레드가 DB를 안
   기다린다"는 것만으로 Tomcat/풀 포화와 그로 인한 대량 실패를 없앤다 —
   여기까진 배치 여부와 무관하다. **배치의 진짜 효과는 응답 지연이
   아니라 "쌓인 걸 실제로 DB에 다 반영하는 데 걸리는 시간"(drain)에서
   드러난다**: 배치 없이(단일 스레드, 커밋마다 fsync 1번) 처리하면
   처리 상한이 초당 ~200건 수준이라 로컬 환경에서도 쉽게 못 따라가고
   백로그가 무한정 쌓이는 반면, 100건 배치는 VU와 무관하게 6~12초 만에
   항상 다 비운다. 상세: [`async/stage-0.md`](async/stage-0.md).
5. **(Stage 1~4 비동기 측정 후 추가)** 위 4번 발견은 데이터 규모가
   커져도(1만→300만) 그대로 유지된다 — **batch100의 drain 시간은
   Stage 0~4 전 구간에서 6~7초(INSERT만)/12~14초(INSERT+UPDATE)로
   완전히 평평**했다. 반대로 **배치 없는 비동기(nobatch)는 데이터가
   커질수록 더 나빠진다** — Stage 0~1(30만 이하)까진 느리지만
   따라갔는데, Stage 2(90만)부터는 가장 가벼운 VU=10 조건에서도 60초
   안에 못 비운다. **결론: 이 실험 범위에서 비동기+배치 적재가
   동기보다 명확히 우세하고, 이 우위는 데이터가 커져도 유지된다.**
   다만 "비동기이기만 하면 낫다"는 틀렸다 — 컨슈머가 배치·병렬 처리
   능력을 안 갖추면 데이터가 커질수록 동기보다 더 빨리 무너질 수
   있다. 상세: [`async/stage-1-to-4.md`](async/stage-1-to-4.md).
