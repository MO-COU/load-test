# 측정 결과 상세

2026-08-31 측정. 조건과 절차는 [CONTRIBUTING.md](../CONTRIBUTING.md) 참고.

```
부하    회원 20,000명이 1인 1요청으로 동시 출발 (k6 per-vu-iterations)
재고    10,000장
구성    EC2 2대 — k6 c5.4xlarge / 앱+MySQL+Redis c5.2xlarge
자원    커넥션 풀 16 · 워커 스레드 200 · accept-count 32768
재시도  서버 5회 + 5~19ms 백오프 (optimistic, redis-watch) · 사용자 재요청 없음
타임아웃 요청 60초 (k6 기본값)
```

브랜치당 2회 측정. 아래 표는 2회의 범위다.

## 종합

| 방식 | 소요 시간 | DB 발급 | 실패율 | p95 | 풀 대기 | 락 대기 | INSERT |
|---|---:|---:|---:|---:|---:|---:|---:|
| `redis-lua` | 8.4~11.5s | 10,000 | 0% | 7.8~11.0s | 184 | 0 | +10,000 |
| `redis-watch` | 11.7~18.6s | 1,580~1,818 | 91~92% | 10.7~17.2s | 0 | 0 | +1.6~1.8k |
| `atomic-update` | 60s+ ⏱ | 10,000 | 53~55% | 59.9s ⏱ | 184 | +19,999 | +10,000 |
| `pessimistic-lock` | 60s+ ⏱ | 10,000 | 54~58% | 59.9s ⏱ | 184 | +19,999 | +10,000 |
| `redisson-rlock` | 60s+ ⏱ | 10,000 | 62~67% | 59.8s ⏱ | 0 | 0 | +10,000 |
| `optimistic` | 60s+ ⏱ | 5,549~5,558 | 74~76% | 59.9s ⏱ | 181 | +88,490 | +88,496 |

모든 방식이 정확히 20,000 요청을 받았다. 락 대기·INSERT 는 측정 전후 증가량이다.

---

## redis-lua

Lua 스크립트로 중복 확인·재고 확인·차감·회원 등록을 Redis 안에서 원자적으로 처리하고,
통과한 요청만 DB 에 이력을 남긴다.

```
k6        8.4s · 20,000 요청 · p95 7.8s · 실패 0%
          발급 10,000 · 품절 10,000 · 완판 7.8~10.7s
dbstat    insert +10,000 · rollback 0 · update 0 · row_lock_waits 0
redis     요청당 EVALSHA 1회
metrics   active 16/16 · pending 184 · threads 200/200
verify    DB 발급 10,000 (완판) · oversell PASS · duplicate PASS · 재고누수 PASS
CPU       us 6~18% · id 75~87% · accept 큐 최대 2,416~13,324
```

품절 1만 건이 Redis 앞에서 끝나 DB 에는 발급 1만 건만 도달했다.
`Com_insert` 가 정확히 발급 수와 일치하고 롤백·락 대기가 0이다.

풀 대기 184 는 DB 방식과 같지만 지속 시간이 다르다. 10초 안에 끝나고 비워진다.

## redis-watch

`WATCH`/`MULTI`/`EXEC` 로 낙관적 예약을 시도하고, 충돌하면 5회까지 재시도한다.

```
k6        11.7~18.6s · 20,000 요청 · p95 10.7~17.2s · 실패 91~92%
          발급 1,580~1,818 · 재고 8,200장 미판매
dbstat    insert +1,580~1,818 · rollback 0 · update 0 · row_lock_waits 0
metrics   active 2~3 · pending 0 · threads 200/200
verify    oversell PASS · duplicate PASS · 재고누수 PASS
CPU       us 14~29% · id 56~71% · accept 큐 최대 4,639~7,747
```

**가장 빨리 끝나지만 가장 적게 팔았다.** 초과 발급은 없으니 정합성은 지켰고,
받을 수 있었던 8,200명이 못 받았다.

스레드 200개가 그대로 Redis 로 몰려 WATCH 충돌이 폭증한다. 확인(`GET`)과
확정(`EXEC`) 사이에 남이 끼어들어 5회 재시도가 대부분 소진된다.

## atomic-update

`UPDATE ... WHERE issued_count < total_quantity` 한 문장으로 재고를 차감한다.

```
k6        60s+ ⏱ · 20,000 요청 · p95 59.9s ⏱ · 실패 53~55%
          k6 발급 9,012~9,449
dbstat    insert +10,000 · rollback +10,000 · update +20,000 · row_lock_waits +19,999
metrics   active 16/16 · pending 184 · threads 200/200
verify    DB 발급 10,000 (완판) · oversell PASS · counter_ok PASS · duplicate PASS
CPU       us 5~11% · id 76~83% · accept 큐 최대 5,761~6,568
```

완판했지만 절반 이상이 60초 안에 답을 못 받았다.
`Com_update` 20,000 은 조건부 UPDATE 가 매 요청 실행된 결과다.

## pessimistic-lock

`SELECT ... FOR UPDATE` 로 쿠폰 행에 배타 락을 걸고 재고 확인부터 증가까지 직렬화한다.

```
k6        60s+ ⏱ · 20,000 요청 · p95 59.9s ⏱ · 실패 54~58%
          k6 발급 8,371~9,118
dbstat    insert +10,000 · rollback +10,000 · update +10,000 · row_lock_waits +19,999
metrics   active 16/16 · pending 184 · threads 200/200
verify    DB 발급 10,000 (완판) · oversell PASS · counter_ok PASS · duplicate PASS
CPU       us 5~9% · id 79~83% · accept 큐 최대 2,557~14,114
```

CPU 는 놀고 있는데 느리다. 락 대기와 커넥션 대기가 병목이라는 뜻이다.
`atomic` 과 락 대기가 19,999 로 같다 — 락을 거는 방법을 바꿔도 줄 서는 구조는 그대로다.

## redisson-rlock

Redis 분산락(`RLock`)을 잡고 그 안에서 DB 트랜잭션을 실행한다.

```
k6        60s+ ⏱ · 20,000 요청 · p95 59.8s ⏱ · 실패 62~67%
          k6 발급 6,601~7,621
dbstat    insert +10,000 · rollback +10,000 · update +10,000 · row_lock_waits 0
metrics   active 1 · pending 0 · threads 200/200
verify    DB 발급 10,000 (완판) · oversell PASS · counter_ok PASS · duplicate PASS
CPU       us 6~10% · id 76~81% · accept 큐 최대 4,288~9,624
```

**Redis 를 쓰고도 DB 방식들보다 실패율이 높다.** 원인은 `active = 1` —
분산락이 전 요청을 직렬화해 DB 커넥션을 동시에 1개만 쓴다.
행 락 대기 0 은 경합을 Redis 로 옮긴 결과지만 그 대가로 병렬성이 사라졌다.

## optimistic

`@Version` 으로 충돌을 감지하고 5회까지 재시도한다.

```
k6        60s+ ⏱ · 20,000 요청 · p95 59.9s ⏱ · 실패 74~76%
          k6 발급 4,709~5,117 · 재고 4,450장 미판매
dbstat    insert +88,496 · rollback +82,947 · update +88,496 · row_lock_waits +88,490
metrics   active 16/16 · pending 180~181 · threads 200/200
verify    DB 발급 5,549~5,558 · oversell PASS · counter_ok PASS · duplicate PASS
CPU       us 27~32% · id 50~54% · accept 큐 최대 2,146~14,585
```

**DB 부하가 압도적으로 많다** — INSERT·락 대기 모두 8.8만으로 다른 방식의 4~9배다.
충돌한 요청이 되돌아와 다시 경합하면서 부하만 키웠다.

재고도 다 팔지 못했다. 재시도 5회 안에 이기지 못한 요청이 그만큼 많았다는 뜻이다.

---

## 해석할 때 주의

**`60s+ ⏱` 는 잘린 값이다.** k6 요청 타임아웃 60초에 걸린 것으로 실제로는 그 이상
걸렸다. 그래서 방식 간 비교에는 소요 시간 대신 **실패율과 DB 발급 수**를 쓴다.

**DB 발급은 서버가 배수를 끝낸 뒤 세었다.** k6 는 60초에서 포기하지만 서버는 밀린
요청을 계속 처리한다. 바로 세면 처리 중인 건이 빠져 실제보다 적게 나온다.

**`Com_update` 는 방식마다 세는 단위가 다르다.** MySQL 은 실행된 UPDATE 문을
세지 변경된 행을 세지 않는다.

| 방식 | `Com_update` 가 세는 것 |
|---|---|
| `pessimistic`·`redisson` | 발급 성공 시 dirty checking 으로 1회 → **발급 수** |
| `atomic-update` | 조건부 UPDATE 가 매 요청 실행 → **전체 요청 수** |
| `optimistic` | 재시도마다 실행 → **시도 수** |

**`counter_ok` 가 Redis 방식에서 N/A 인 이유.** 재고 판정을 Redis 가 하므로
`coupon.issued_count` 를 갱신하지 않는다. 모든 요청이 같은 행을 UPDATE 하면
직렬화되어 인메모리 판정의 이점이 사라지기 때문이다.

**Redis 는 포화되지 않았다.** `lua` 가 `watch` 보다 초당 더 많은 요청을 처리하고도
오류가 0이었다는 점이 `watch` 의 실패가 Redis 성능이 아니라 WATCH 충돌 때문임을
보여준다.

**accept 큐 최대 깊이는 2,146~14,585 였다.** Tomcat 기본값 100 이었다면 연결이
대량 폐기됐을 것이다. `ListenOverflows` 는 전 회차 0 으로, 설정한 32768 은 충분했다.
