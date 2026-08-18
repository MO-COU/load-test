# 측정 결과 상세

2026-08-17 측정. 조건과 절차는 [CONTRIBUTING.md](../CONTRIBUTING.md) 참고.

```
부하    0 → 20,000 VU, 60초 램프업
재고    10,000장 / 회원 20,000명
구성    EC2 2대 — k6 / 앱 + MySQL + Redis
자원    커넥션 풀 50 · 워커 스레드 200 · Tomcat max-connections 30,000
```

## 종합

| 방식 | 처리 req/s | 총 요청 | p95 | 발급 | 오류 | 풀 대기 | 락 대기 | INSERT |
|---|---:|---:|---:|---|---:|---:|---:|---:|
| `pessimistic-lock` | 369 | 30,838 | 47.2s | 10,000 | 0 | 149 | +30,815 | +14,780 |
| `optimistic` | 134 | 12,089 | 60s+ ⏱ | 7,976 | 9,799 | 149 | +87,675 | +82,505 |
| `atomic-update` | 400 | 32,286 | 43.7s | 10,000 | 0 | 149 | +32,285 | +15,709 |
| `redisson-rlock` | 149 | 13,435 | 60s+ ⏱ | 9,457 | 2,839 | 0 | 0 | +12,685 |
| `redis-lua` | 12,399 | 761,046 | 1.31s | 10,000 | 0 | 0 | 0 | +10,000 |
| `redis-watch` | 10,165 | 622,838 | 1.27s | 10,000 | 3,823 | 0 | 0 | +10,000 |

발급 수는 `coupon_issue` 행 수 기준. 락 대기·INSERT 는 측정 전후 증가량.

---

## pessimistic-lock

`SELECT ... FOR UPDATE` 로 쿠폰 행에 배타 락을 걸고 재고 확인부터 증가까지 직렬화한다.

```
k6        369 req/s · 30,838 요청 · p95 47.2s · avg 31.6s · errors 0
          k6 발급 10,000 · 품절 16,021 · 중복 4,817
dbstat    insert +14,780 · rollback +20,816 · update +10,000
          row_lock_waits +30,815 · lock_time_avg 129ms
metrics   active 50/50 · pending 149 · threads 200/200  (부하 시작 수 초 만에 포화)
verify    DB 발급 10,000 (완판) · oversell PASS · counter_ok PASS · duplicate PASS
```

완판하고 오류도 없지만 모든 요청이 락 앞에 줄을 서 p95 47초.
1차 측정(369.1 req/s, p95 47.17s)과 재측정(369.8, 47.09)이 거의 일치해
단일 측정의 재현성을 뒷받침한다.

## optimistic

`@Version` 으로 충돌을 감지하고 5회까지 재시도한다.

```
k6        134 req/s · 12,089 요청 · p95 60s+ ⏱ · errors 9,799 (81.05%)
          k6 발급 1,950 · 중복 340
dbstat    insert +82,505 · rollback +74,529 · update +80,784
          row_lock_waits +87,675 · lock_time_avg 106ms
metrics   active 50/50 · pending 95~149 · threads 200/200
verify    DB 발급 7,976 (재고 2,024장 미소진) · oversell PASS · counter_ok PASS · duplicate PASS
```

고경합에서 붕괴했다. 81% 가 실패하고 60초 안에 재고를 다 팔지 못했는데,
**DB 부하는 6개 중 최다**다 — INSERT 8.2만, 롤백 7.5만, 락 대기 8.8만.
재시도가 처리량을 낮추면서 부하만 키운 결과다.

정합성 자체는 지켰다. 덜 준 것이지 더 준 것이 아니다.

## atomic-update

`UPDATE ... WHERE issued_count < total_quantity` 한 문장으로 재고를 차감한다.

```
k6        400 req/s · 32,286 요청 · p95 43.7s · avg 28.6s · errors 0
          k6 발급 10,000 · 품절 16,577 · 중복 5,709
dbstat    insert +15,709 · rollback +22,286 · update +32,286
          row_lock_waits +32,285 · lock_time_avg 109ms
metrics   active 50/50 · pending 109~149 · threads 161~200
verify    DB 발급 10,000 (완판) · oversell PASS · counter_ok PASS · duplicate PASS
```

DB 판정 방식 중 가장 빠르지만 `pessimistic` 과 8% 차이다.
락을 거는 방법을 바꿔도 **같은 행을 두고 직렬화된다는 구조**는 그대로다.

## redisson-rlock

Redis 분산락(`RLock`)을 잡고 그 안에서 DB 트랜잭션을 실행한다.

```
k6        149 req/s · 13,435 요청 · p95 60s+ ⏱ · errors 2,839 (21.13%)
          k6 발급 7,941 · 중복 2,655
dbstat    insert +12,685 · rollback +3,228 · update +9,459
          row_lock_waits +0 · lock_time_avg 변화 없음
metrics   active 1 · pending 0 · threads 200/200
verify    DB 발급 9,457 (재고 543장 미소진) · oversell PASS · duplicate PASS
```

**Redis 를 쓰고도 DB 방식보다 느렸다.** 원인은 `metrics` 의 `active = 1` 이
한 줄로 설명한다 — 분산락이 전 요청을 직렬화해 DB 커넥션을 동시에 1개만 쓴다.

행 락 대기가 0인 것은 락 경합을 Redis 로 옮긴 결과지만,
그 대가로 병렬성이 사라졌다. 락만 인메모리로 옮기는 것으로는
DB 판정의 한계를 벗어나지 못한다.

## redis-lua

Lua 스크립트로 중복 확인·재고 확인·차감·회원 등록을 Redis 안에서 원자적으로 처리하고,
통과한 요청만 DB 에 이력을 남긴다.

```
k6        12,399 req/s · 761,046 요청 · p95 1.31s · avg 806ms · errors 0
          k6 발급 10,000 · 품절 139,820 · 중복 611,226
dbstat    insert +10,000 · rollback 0 · update 0 · row_lock_waits 0
metrics   active 1~21 (대부분 한 자릿수) · pending 0 · threads 200/200
verify    DB 발급 10,000 (완판) · oversell PASS · counter_ok N/A · duplicate PASS
          재고누수 PASS (발급 10,000 + 남은재고 0 = 10,000)
```

76만 요청 중 **75만 건의 품절·중복을 Redis 가 쳐내** DB 에는 발급 10,000건만 도달했다.
`Com_insert` 가 정확히 발급 수와 일치하고 롤백이 0이다.

원자적 실행이라 충돌 자체가 없어 오류 0. Redis 재고와 발급자 명단이
DB 기록과 정확히 일치해 보상 로직도 검증됐다.

## redis-watch

`WATCH`/`MULTI`/`EXEC` 로 낙관적 예약을 시도하고, 충돌하면 5회까지 재시도한다.

```
k6        10,165 req/s · 622,838 요청 · p95 1.27s · avg 983ms · errors 3,823 (0.61%)
          k6 발급 10,000 · 품절 446,698 · 중복 162,317
dbstat    insert +10,000 · rollback 0 · update 0 · row_lock_waits 0
metrics   active 2~7 · pending 0 · threads 200/200
verify    DB 발급 10,000 (완판) · oversell PASS · counter_ok N/A · duplicate PASS
          재고누수 PASS (발급 10,000 + 남은재고 0 = 10,000)
```

`lua` 와 같은 인메모리 판정이라 처리량·자원 사용이 비슷하다.
차이는 **재시도 소진 3,823건이 5xx 로 나갔다**는 점이다.

같은 낙관적 계열인 `optimistic` 이 81% 실패한 것과 대비된다.
판정이 인메모리에 있으면 재시도 비용이 훨씬 싸다.

---

## 해석할 때 주의

**발급 수는 DB 행 수 기준이다.** k6 는 60초에서 포기하지만 서버는 처리를 끝낸다.
그래서 `optimistic`(k6 1,950 / DB 7,976)과 `redisson`(7,941 / 9,457)은 값이 다르다.

**`counter_ok` 가 Redis 방식에서 N/A 인 이유.** 재고 판정을 Redis 가 하므로
`coupon.issued_count` 를 갱신하지 않는다. 모든 요청이 같은 행을 UPDATE 하면
직렬화되어 인메모리 판정의 이점이 사라지기 때문이다. 카운터가 0 이라 비교할
대상이 없어 N/A 다.

**`Com_update` 는 방식마다 세는 단위가 다르다.** MySQL 은 실행된 UPDATE 문을
세지 변경된 행을 세지 않는다.

| 방식 | `Com_update` 가 세는 것 |
|---|---|
| `pessimistic`·`redisson` | 발급 성공 시 dirty checking 으로 1회 → **발급 수** |
| `atomic-update` | 조건부 UPDATE 가 매 요청 실행 → **전체 요청 수** |
| `optimistic` | 재시도마다 실행 → **시도 수** |

`atomic` 의 `+32,286` 이 `pessimistic` 의 `+10,000` 보다 큰 것은 DB 를 세 배
많이 쓴 것이 아니라 세는 단위가 다른 것이다.

**p95 의 `60s+` 는 클립된 값이다.** k6 요청 타임아웃에 잘린 것으로 실제 대기는 그 이상이다.

**브랜치당 1회 측정이다.** 그룹 간 격차(20~30배)는 확정적이지만,
그룹 안 순위(`lua` vs `watch` 18%, `atomic` vs `pessimistic` 8%)는 노이즈 범위라
주장하지 않는다. `pessimistic` 은 2회 측정이 369↔370 req/s 로 일치해
단일 측정의 신뢰를 뒷받침한다.

**`redisson` 의 재고누수 FAIL 은 오탐이었다.** 초기화 시 세팅된 미사용 Redis 키를
검증 스크립트가 오인한 것으로, 이 방식은 재고를 DB 에서 관리한다.
측정값 자체는 오염되지 않았다.

**인메모리 방식도 워커 스레드는 200/200 이다.** 다만 DB 판정은 요청당 수십 초
점유하는 200 이고, 인메모리는 밀리초에 회전하는 200 이다.
"스레드 확보"가 아니라 "스레드 점유 시간 단축"으로 읽어야 정확하다.

**포화 구간의 metrics 표본에 공백이 있다.** 수집 요청 자체가 부하에 밀린 것으로,
공백 자체가 포화의 증거다. 값은 그 구간 내내 일정했다.
