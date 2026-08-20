# DB 적재 방식 비교 실험 (동기 vs 비동기)

**진행 상태(2026-08-20): 동기·비동기 모두 Stage 0~4(배경 데이터
1만~300만 건) 측정 완료.** 최종 결론은
[`benchmark-results/sync-vs-async/README.md`](benchmark-results/sync-vs-async/README.md)의
"요약" 표와 "핵심 발견"을 참고 — 이 실험 범위에서 비동기+배치 적재가
동기보다 우세하고, 이 우위는 데이터가 커져도 유지된다는 결론이 나왔다.

## 목적

Redis 등 앞단에서 이미 발급 대상이 정해졌다고 가정하고, 그 결과를 DB에
적재하는 단계만 떼어내어 부하가 얼마나 오는지, 어디까지 올렸을 때 성능이
무너지는지, 동기 저장과 비동기(배치) 저장 중 어떤 방식이 효율적인지
비교한다. 결과를 바탕으로 DB 저장 방식을 결정한다.

재고 판정 방식(Redis Lua, WATCH 등)은 이 실험과 무관하다. 여기서는 "이미
확정된 발급 결과를 어떻게 적재하는가"만 본다.

**Tomcat 스레드·HikariCP 풀 포화는 참고 정보일 뿐, 최종 판단 기준이
아니다.** 비동기가 이 둘을 훨씬 여유 있게 쓴다는 건 사실이지만, 그건
지금 벤치마크 API(`BenchmarkCouponIssueController`)가 "HTTP 요청이 DB에
직접 간다"는 구조라서 생기는 특성이다. 실제 목표 아키텍처는 Redis(Lua)가
이미 재고 판정을 끝낸 뒤의 DB 적재 단계만 비교하는 것이므로, 그
아키텍처에서는 HTTP 스레드가 애초에 DB를 직접 안 건드린다. 자세한 논의는
[analysis-notes.md의 7장](benchmark-results/sync-vs-async/analysis-notes.md#7-비동기배치-적재로-바꾸면-예상되는-변화)
참고.

## 이 실험이 답하는 질문

- INSERT 단독, INSERT+UPDATE 혼합 부하에서 동기 적재는 어디까지 버티는가?
- 같은 부하에서 비동기(배치) 적재는 connection pool을 얼마나 아끼고,
  처리량은 얼마나 올라가는가?
- 부하를 얼마나 올렸을 때 커넥션 풀 고갈, 지연시간 급증, 에러율 상승 등
  "성능이 터지는" 지점이 나타나는가? 동기/비동기 방식별로 그 지점이 다른가?
- 비동기로 적재를 미루면 정합성(적재 성공 여부, 유실·중복)은 어떻게
  보장되는가?

## 범위와 제외 범위

| 구분 | 이 실험 | 제외 |
| --- | --- | --- |
| 대상 | `coupon_issue` INSERT, status UPDATE | 재고 판정 로직(Redis Lua/WATCH 등) — 이미 발급 대상이 확정됐다고 가정 |
| 비교축 | 동기 저장 vs 비동기(배치) 저장 | 인덱스·쿼리 최적화([large-db-experiment.md](large-db-experiment.md)의 조회·집계 실험에서 다룸) |
| 관찰 지표 | connection pool 사용량, 적재 속도(처리량·지연), 정합성(적재 성공 건수) | 조회·집계 성능 |
| 결과 활용 | ERD 개선안 도출 | - |

같은 저장소의 [large-db-experiment.md](large-db-experiment.md)(조회·집계
성능, 인덱스 최적화)와는 별도 관심사다. 그 실험은 "많이 쌓인 상태에서
조회가 느린가"를 다루고, 이 실험은 "많은 쓰기 요청이 몰릴 때 어떻게
적재해야 하는가"를 다룬다.

## 데이터 규모 및 부하 단계

`docs/large-db-experiment.md`의 Stage 1~4(30만·90만·150만·300만)에 **Stage 0(1만
건)** 을 앞에 추가한 것으로 본다. Stage 1~4는 기존 `seed-stage.sql`을
`@member_count`만 바꿔 그대로 재사용하고, Stage 0은 `coupon_issue`가
`member_count * 3`이라 정수로 정확히 10,000을 못 만들어(3,334 -> 10,002)
전용 스크립트 `scripts/large-db/seed-stage0-trim.sql`을 새로 만들었다.
`seed-stage.sql`을 그대로 `source`한 뒤 초과분 2건만 지워 `coupon_issue`를
정확히 10,000건으로 맞춘다(`seed-stage.sql` 자체는 수정하지 않았다).

| 단계 | MEMBER | COUPON_ISSUE(배경 데이터) | 비고 |
| --- | ---: | ---: | --- |
| Stage 0 | 3,334 | 정확히 10,000 | 이번 실험에서 새로 추가, `seed-stage0-trim.sql` |
| Stage 1 | 100,000 | 300,000 | 기존 실험과 공유 |
| Stage 2 | 300,000 | 900,000 | 기존 실험과 공유 |
| Stage 3 | 500,000 | 1,500,000 | 기존 실험과 공유 |
| Stage 4 | 1,000,000 | 3,000,000 | 기존 실험과 공유 |

각 단계에서 INSERT 10,000건, INSERT+UPDATE 10,000건을 실행해 속도와 커넥션
풀을 비교한다. 요청 건수(10,000)는 단계가 올라가도 고정하고, **배경
데이터(테이블에 이미 쌓인 행 수)만 단계별로 늘려** "테이블이 커질수록 같은
쓰기 부하가 더 무거워지는가"를 본다.

## 1차로 볼 것: INSERT만 vs INSERT+UPDATE

같은 Stage(우선 Stage 0)에서 두 워크로드를 나란히 비교한다.

| 워크로드 | 스크립트 | 대상 |
| --- | --- | --- |
| INSERT만 | `load-test/large-db-insert.js` | `coupon_issue` 신규 행 저장만 |
| INSERT + UPDATE | `load-test/large-db-insert-then-update.js` | 저장 직후 같은 행의 상태를 `ISSUED → USED`로 변경(발급 후 즉시 사용 처리하는 흐름을 가정) |

둘 다 현재는 동기(단건 `JdbcTemplate`) 경로만 탄다. 비동기 적재 경로가
생기면 같은 두 워크로드를 비동기로도 돌려 표를 채운다.

## 비교 방식

| 방식 | 설명 | 관찰 대상 |
| --- | --- | --- |
| 동기 저장 | 요청마다 즉시 INSERT/UPDATE, 트랜잭션 커밋까지 응답 대기 | HikariCP pool 점유 시간, p95, 커넥션 대기 |
| 비동기(배치) 저장 | 요청은 큐/버퍼에만 적재하고 즉시 응답, 별도 워커가 모아서 배치로 INSERT | 배치 크기·주기별 처리량, 큐 적체, 적재 지연, 유실·중복 여부 |

**배치는 큐/컨슈머를 쓴다고 자동으로 생기는 게 아니다.** 컨슈머가
메시지를 1건씩 읽어서 1건씩 INSERT하면 동기와 똑같이 "1행 = 1커밋"이라
fsync 이득이 전혀 없다. N건을 모아 하나의 트랜잭션으로 커밋하는 로직을
컨슈머 코드에 명시적으로 구현해야 배치 효과가 생긴다.

## 관측 지표

| 지표 | 출처 | 의미 |
| --- | --- | --- |
| `hikaricp_connections_active/pending` | `/actuator/prometheus` | DB 커넥션 풀 고갈 여부 |
| `tomcat_threads_busy` | `/actuator/prometheus` | HTTP 요청을 받는 워커 스레드 포화 여부(커넥션 풀과 별개 자원) |
| `Innodb_buffer_pool_reads` / `read_requests` | MySQL `SHOW GLOBAL STATUS` | 버퍼 풀 캐시 미스율 — 배경 데이터가 커질수록(Stage 2~4) 중요해짐 |
| `Innodb_os_log_fsyncs` | MySQL `SHOW GLOBAL STATUS` | 커밋마다 발생하는 redo log fsync 횟수 — 동기(요청당 fsync 1회) vs 비동기(배치당 fsync 1회) 차이의 핵심 |
| `Innodb_row_lock_waits` | MySQL `SHOW GLOBAL STATUS` | 의도치 않은 행 잠금 경합이 있는지(0이어야 정상) |
| Avg, p95, 처리량 | k6 요약 | 사용자 체감, 실제 처리 능력 |
| 적재 성공 건수 vs 요청 건수 | 검증 스크립트 | 정합성(유실·중복 여부) |
| 오류율 | k6 `http_req_failed` | 실패가 시작되는 시점 |

위 다섯 개(HikariCP·Tomcat·InnoDB 버퍼 풀·fsync·row lock)는
`scripts/large-db/collect-pool-metrics.sh`가 부하 도중 1초 간격으로 자동
기록한다.

## 실험 절차

1. ~~actuator·micrometer 의존성을 추가해 HikariCP 지표를 노출한다.~~ 완료
2. ~~비동기(배치) 적재 경로를 구현한다.~~ 완료 —
   `AsyncIssueQueue`/`AsyncCouponIssueConsumer`(단일 컨슈머 스레드,
   `BATCH_SIZE`/`BATCH_INTERVAL_MS` 설정)
3. ~~동기·비동기 각각 INSERT 10,000건, UPDATE+INSERT 각 10,000건을
   측정한다.~~ 완료 — Stage 0~4 전 구간
4. ~~부하를 점진적으로 올리며 각 방식이 무너지는 지점(지연 급증·오류율
   상승·풀 고갈)을 기록한다.~~ 완료 — VU 10~500 스윕, 동기는
   Tomcat/풀 포화·TCP 연결 거부, 비동기는 drain 시간으로 무너지는
   지점을 확인
5. ~~두 방식의 connection pool 사용량, 처리량, 정합성을 나란히
   비교한다.~~ 완료 — 정합성은 Stage 0 규모 재현 테스트로 확인(유실·
   중복 0건)
6. **결과를 바탕으로 ERD 개선안을 정리한다. — 다음에 할 일**

측정 결과 전체는
[`benchmark-results/sync-vs-async/README.md`](benchmark-results/sync-vs-async/README.md)
(요약)과 그 아래 `sync/`, `async/`, `analysis-notes.md`(상세 해석)에
있다.

## Stage 0 실행 방법

아래는 **순정 PowerShell** 기준이다(Git Bash/WSL을 쓴다면 각주의 bash 버전을
쓴다). `docker compose exec`/`mysql -e "source ..."` 계열은 한 줄로 쓰면
bash·PowerShell·cmd 어디서나 그대로 동작하므로 줄바꿈(`\`) 없이 썼다.

```powershell
# 1. 대용량 DB 컨테이너 + 앱(large-db 프로필) — 이 창은 계속 떠 있는 상태로 둔다
docker compose -f docker-compose.large-db.yml up -d
.\gradlew.bat bootRun --args='--spring.profiles.active=large-db'
```

```powershell
# 2. (새 터미널) 지표 이름 확인 — 앱이 완전히 뜬 뒤 1회만
# curl(별칭)이 Invoke-WebRequest로 잡혀 -Uri를 못 받는 경우가 있어 curl.exe로 명시한다
curl.exe -s localhost:8080/actuator/prometheus | Select-String -Pattern 'hikaricp_connections|tomcat_threads'
```

```powershell
# 3. Stage 0 배경 데이터 시드(정확히 10,000건)
docker compose -f docker-compose.large-db.yml exec -T mysql-large mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/seed-stage0-trim.sql"
```

```powershell
# 4. INSERT만 — 부하 시작 직전, 별도 터미널에서 풀 지표 기록 시작
.\scripts\large-db\collect-pool-metrics.ps1 -Name insert-only-stage0
```
```powershell
# (다른 터미널) 초기화 후 부하
docker compose -f docker-compose.large-db.yml exec -T mysql-large mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/prepare-benchmark.sql"
k6 run -e VUS=10 -e ITERATIONS_PER_VU=1000 load-test/large-db-insert.js
```
부하 끝나면 `collect-pool-metrics.ps1` 창에서 `Ctrl+C`.

```powershell
# 5. INSERT+UPDATE — 마찬가지로 별도 터미널에서 기록 시작
.\scripts\large-db\collect-pool-metrics.ps1 -Name insert-update-stage0
```
```powershell
docker compose -f docker-compose.large-db.yml exec -T mysql-large mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/prepare-benchmark.sql"
k6 run -e VUS=10 -e ITERATIONS_PER_VU=1000 load-test/large-db-insert-then-update.js
```
부하 끝나면 `collect-pool-metrics.ps1` 창에서 `Ctrl+C`.

```powershell
# 6. 검증(정합성)
docker compose -f docker-compose.large-db.yml exec -T mysql-large mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/verify-benchmark.sql"
```

`collect-pool-metrics.ps1`(순정 PowerShell용) / `collect-pool-metrics.sh`(Git
Bash·WSL용)는 같은 일을 한다 — HikariCP 커넥션 풀, Tomcat 워커 스레드,
InnoDB 버퍼 풀(히트율·fsync·row lock)을 1초 간격으로
`docs/benchmark-results/sync-vs-async/raw/<이름>.tsv`에 기록한다.

Stage 1~4로 올릴 때는 3번 대신 기존 `seed-stage.sql`을 `@member_count`만 각 단계
값(100000·300000·500000·1000000)으로 바꿔서 쓴다.

```powershell
docker compose -f docker-compose.large-db.yml exec -T mysql-large mysql -ucoupon_large -pcoupon-large-1234 --init-command="SET @member_count = 100000" coupon_large -e "source /scripts/large-db/seed-stage.sql"
```

<details>
<summary>Git Bash / WSL 버전 (참고용, 줄바꿈 가능)</summary>

```bash
curl -s localhost:8080/actuator/prometheus | grep -E 'hikaricp_connections|tomcat_threads'

docker compose -f docker-compose.large-db.yml exec -T mysql-large \
  mysql -ucoupon_large -pcoupon-large-1234 coupon_large \
  -e "source /scripts/large-db/seed-stage0-trim.sql"

bash scripts/large-db/collect-pool-metrics.sh insert-only-stage0
bash scripts/large-db/collect-pool-metrics.sh insert-update-stage0
```

</details>

## 준비 상태 (2026-08-20 기준)

`experiment/large-db-benchmark`에서 갈라져 나온 브랜치(`exp/large-db-sync-vs-async`)이며,
동기·비동기 측정에 필요한 것은 전부 갖춰져 있고 Stage 0~4 측정도 끝났다
(전부 아직 uncommitted).

- 스키마: `scripts/large-db/schema.sql`, 시드: `scripts/large-db/seed-stage.sql`
  (Stage 1~4), `scripts/large-db/seed-stage0-trim.sql`(Stage 0, `coupon_issue`
  정확히 10,000건)
- 동기 k6 스크립트: `load-test/large-db-insert.js`(INSERT만),
  `load-test/large-db-insert-then-update.js`(INSERT+UPDATE)
  (`VUS`, `ITERATIONS_PER_VU` 환경변수로 요청 건수 조절 가능)
- 비동기 k6 스크립트: `load-test/large-db-insert-async.js`,
  `load-test/large-db-insert-then-update-async.js` — `202 Accepted` 계약
  (큐 적재 확인일 뿐 DB 반영은 별도)
- 동기 적재 API: `BenchmarkCouponIssueController` / `Service` / `Repository`
  (`JdbcTemplate` 단건 처리)
- 비동기(배치) 적재 경로: `AsyncIssueQueue`(인메모리, unbounded) +
  `AsyncCouponIssueConsumer`(단일 컨슈머 스레드, `BATCH_SIZE`/
  `BATCH_INTERVAL_MS`로 배치 크기·주기 조절 — 기본값 100건/100ms,
  `BATCH_SIZE=1`이면 배치 없음과 동일)
- actuator·micrometer 의존성 및 `/actuator/prometheus` 노출
  (`application-large-db.yaml`의 `management.endpoints.web.exposure`,
  Tomcat 스레드 지표 노출을 위한 `server.tomcat.mbean-registry.enabled`도 포함)
- 커넥션 풀·Tomcat 스레드·InnoDB 버퍼 풀 자동 기록 —
  `scripts/large-db/collect-pool-metrics.ps1`(순정 PowerShell),
  `collect-pool-metrics.sh`(Git Bash/WSL)
- VU 스윕(부하를 점진적으로 올려 실패 지점을 찾는 시나리오) —
  `scripts/large-db/run-vu-sweep.sh`(동기), `run-vu-sweep-async.sh`
  (비동기, k6 종료 후 큐가 다 빌 때까지 drain 대기 포함)
- 결과: [`benchmark-results/sync-vs-async/`](benchmark-results/sync-vs-async/README.md)
  — 동기(`sync/stage-{0..4}.md`)·비동기(`async/stage-0.md`,
  `async/stage-1-to-4.md`) 전 구간, 해석은 `analysis-notes.md`

남은 건 이 결과를 바탕으로 한 **ERD 개선안 정리**뿐이다.
