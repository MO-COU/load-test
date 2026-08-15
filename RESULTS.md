# 측정 결과

- 정합성은 각자 로컬에서 확인하고, **전원 통과한 뒤** 성능 측정을 시작한다.
- 성능은 대표 1명이 아래 EC2 환경에서 7개를 모두 측정한다.
- 브랜치당 워밍업 1회를 버리고 3회를 기록한다. 대표값은 중앙값.
- 환경 값이 하나라도 다른 회차는 버린다.

절차는 [README.md](README.md), 실행 명령은 `scripts/setup-*.sh`가 등록하는
`runapp` / `dbreset` / `dbverify` / `runk6`를 쓴다.

## 환경

| 항목 | 값 |
|---|---|
| k6 인스턴스 | c5.4xlarge / 20GB gp3 |
| 앱+DB 인스턴스 | c5.2xlarge / 30GB gp3 |
| 리전 / AZ | ap-northeast-2 / k6=?, 앱=? |
| DB_POOL_SIZE | 50 |
| TOMCAT_MAX_THREADS | 200 |
| VU / 시간 | 20000 / 60s |
| total_quantity | 10000 |
| MEMBER_POOL | 20000 |
| 측정일 | |
| 측정자 | |

> 고정 성능 타입(c5/c6i/m5)과 gp3를 쓴다. t 시리즈와 gp2는 크레딧이 고갈되면
> 나중에 측정한 방식일수록 불리해져서, 측정 순서가 곧 결과가 된다.
>
> VU 20000 은 k6 자체가 메모리를 많이 쓴다. c5.4xlarge(16 vCPU / 32GB) 미만이면
> 부하 생성기가 먼저 한계에 걸려 앱이 아니라 k6 를 측정하게 된다.
> 측정 중 k6 서버에서 `free -g` 로 여유 메모리를 확인한다.

## 판정 기준

| 항목 | 기준 |
|---|---|
| 초과·누락 발급 | `issued_count` = `total_quantity` = 10000 |
| 카운터 일치 | `issued_count` = `issued_rows` |
| 1인 1매 | 중복 회원 0행 |
| 에러 | `errors` 0 (`exp/redis-watch` 제외, 아래 참고) |

## 종합

| 방식 | 브랜치 | 정합성 | req/s | p95 | 한 줄 평 |
|---|---|---|---|---|---|
| baseline | `feature/baseline` | FAIL (설계상) | | | 비교 기준점 |
| 비관적 락 | `exp/pessimistic-lock` | | | | |
| 낙관적 락 | `exp/optimistic` | | | | |
| 원자적 UPDATE | `exp/atomic-update` | | | | |
| Redisson RLock | `exp/redisson-rlock` | | | | |
| Lettuce + Lua | `exp/redis-lua` | | | | |
| Lettuce WATCH | `exp/redis-watch` | | | | |

req/s와 p95는 3회 중앙값.

---

## 측정 방법

브랜치마다 아래를 반복한다. `runapp`이 브랜치와 커밋 해시를 출력하므로,
아래 표의 커밋이 실제 측정 대상과 같은지 확인하고 다르면 고쳐 적는다.

```
[앱 ①]  runapp <브랜치>
[앱 ②]  dbreset            ← Redis 재고를 쓰는 브랜치는 dbreset redis
[k6 ③]  runk6 <라벨> <회차>
[앱 ②]  dbverify
```

표의 `count` / `rows` / `중복`은 `dbverify` 출력, 나머지는 `runk6` 출력이다.

---

### baseline — `feature/baseline` (4afde4e)

초기화 `dbreset` · 라벨 `baseline`

| 회차 | req/s | p95 | max | issued | sold_out | dup | errors | count | rows | 중복 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | |
| 2 | | | | | | | | | | |
| 3 | | | | | | | | | | |
| **중앙값** | | | | | | | | | | |

> 동시성 제어가 없어 초과 발급이 나는 것이 정상이다. 통과 여부가 아니라
> 다른 방식이 이 숫자를 얼마나 교정하는지를 보기 위한 기준점이다.

특이 로그 ·

해석 ·

---

### 비관적 락 — `exp/pessimistic-lock` (ae50afd)

초기화 `dbreset` · 라벨 `pessimistic`

| 회차 | req/s | p95 | max | issued | sold_out | dup | errors | count | rows | 중복 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | |
| 2 | | | | | | | | | | |
| 3 | | | | | | | | | | |
| **중앙값** | | | | | | | | | | |

> 락 대기가 커넥션을 점유해 풀 고갈로 번질 수 있다.
> `errors`가 0이어도 앱 로그에 `Connection is not available`이 남았는지 확인한다.

특이 로그 ·

해석 ·

---

### 낙관적 락 — `exp/optimistic` (3700abe)

초기화 `dbreset` · 라벨 `optimistic`

| 회차 | req/s | p95 | max | issued | sold_out | dup | errors | count | rows | 중복 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | |
| 2 | | | | | | | | | | |
| 3 | | | | | | | | | | |
| **중앙값** | | | | | | | | | | |

> 버전 충돌 시 `while (true)`로 무한 재시도한다. 실패가 에러로 드러나지 않고
> **응답 시간으로만 나타나므로** `errors`보다 p95·max를 봐야 한다.

특이 로그 · `ObjectOptimisticLockingFailureException` 재시도 횟수:

해석 ·

---

### 원자적 UPDATE — `exp/atomic-update` (48e6266)

초기화 `dbreset` · 라벨 `atomic`

| 회차 | req/s | p95 | max | issued | sold_out | dup | errors | count | rows | 중복 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | |
| 2 | | | | | | | | | | |
| 3 | | | | | | | | | | |
| **중앙값** | | | | | | | | | | |

> 조건부 UPDATE 한 문장으로 판정이 DB 안에서 끝나, 락을 쥔 채 앱까지
> 왕복하지 않는다. 비관적 락과의 처리량 차이가 그 왕복 비용이다.

특이 로그 ·

해석 ·

---

### Redisson RLock — `exp/redisson-rlock` (a0157d9)

초기화 `dbreset` · 라벨 `redisson`

재고는 DB로 관리하고 Redis는 락(`coupon:{id}:issue:lock`)에만 쓴다.
락 설정 (waitTime / leaseTime):

| 회차 | req/s | p95 | max | issued | sold_out | dup | errors | count | rows | 중복 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | |
| 2 | | | | | | | | | | |
| 3 | | | | | | | | | | |
| **중앙값** | | | | | | | | | | |

> leaseTime이 임계구역보다 짧으면 작업 도중 락이 자동 해제되어 두 요청이
> 함께 들어간다. 초과 발급이 나면 락 로직보다 leaseTime을 먼저 의심한다.

특이 로그 · 락 획득 실패(waitTime 초과):

해석 ·

---

### Lettuce + Lua — `exp/redis-lua` (fdd2e1e)

초기화 **`dbreset redis`** · 라벨 `lua`

| 회차 | req/s | p95 | max | issued | sold_out | dup | errors | count | rows | 중복 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | |
| 2 | | | | | | | | | | |
| 3 | | | | | | | | | | |
| **중앙값** | | | | | | | | | | |

Redis 잔여 재고 (`dbverify` 마지막 줄): 1회 ___ / 2회 ___ / 3회 ___

> `DECR`로 재고를 깎은 뒤 DB 반영이 실패하면 Redis 카운터는 자동 복구되지
> 않는다. 잔여 재고와 `issued_rows`의 합이 1000이 아니면 그 자체가 발견이다.

특이 로그 ·

해석 ·

---

### Lettuce WATCH/MULTI/EXEC — `exp/redis-watch` (e5f71ac)

초기화 **`dbreset redis`** · 라벨 `watch`

재시도 한도(MAX_RETRY):

| 회차 | req/s | p95 | max | issued | sold_out | dup | errors | count | rows | 중복 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | | | | | | | | | | |
| 2 | | | | | | | | | | |
| 3 | | | | | | | | | | |
| **중앙값** | | | | | | | | | | |

Redis 잔여 재고 (`dbverify` 마지막 줄): 1회 ___ / 2회 ___ / 3회 ___

> **이 브랜치만 `errors` 0이 기준이 아니다.** 재시도 한도를 넘기면 의도적으로
> 5xx를 낸다. 쿠폰 키 하나에 2000 VU가 몰리므로 EXEC 충돌이 폭주할 수 있고,
> 그 건수 자체가 "고경합에서 WATCH의 한계"라는 측정 결과다.
>
> 재고 키와 발급자 Set을 Redis에 두고 DB 실패 시 `INCR`/`SREM`으로 되돌린다.
> 보상이 누락되면 Redis 잔여 재고가 DB와 어긋난다.

특이 로그 · 재시도 한도 초과(5xx) 건수:

해석 ·
