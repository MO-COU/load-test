# 선착순 쿠폰 발급 방식 비교

같은 요구사항을 6가지 동시성 제어 방식으로 구현하고, 동일 조건에서 비교한다.
`main`은 동시성 제어가 없는 baseline이며 각 방식은 `exp/*` 브랜치에 있다.

## 무엇을 밝히려는가

DB 락으로 정합성을 지키면 락 경합 때문에 커넥션 풀과 워커 스레드가 고갈된다.
재고 판정을 Redis(인메모리)로 옮기면 그 자원을 얼마나 확보할 수 있는가.

```
DB 락 방식     요청 전부가 DB 락을 거침 → 직렬화
Redis 방식     Redis 가 먼저 판정 → 거절될 요청은 DB 에 도달하지 않음
```

## 6가지 방식

동시성 제어 방법은 셋뿐이고, 각각을 DB 와 Redis 로 구현한 3쌍이다.

| 전략 | DB | Redis |
|---|---|---|
| **대기** 락을 걸고 시작 | `pessimistic-lock` | `redisson-rlock` |
| **재시도** 충돌하면 다시 | `optimistic` | `redis-watch` |
| **원자적** 한 번에 처리 | `atomic-update` | `redis-lua` |

재시도 정책이 필요한 건 가운데 줄뿐이다. 대기형은 기다리면 되고, 원자형은 실패가 없다.

---

# 시작하기

## 사전 준비

- JDK 21
- Docker
- [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/)

## 실행

```bash
docker compose up -d
docker compose ps          # mysql, redis 모두 healthy 확인
./gradlew bootRun          # Windows: .\gradlew.bat bootRun
```

스키마와 시드는 컨테이너가 처음 뜰 때 자동 적용된다.

> 스키마를 바꿨다면 `docker compose down -v` 로 볼륨까지 지워야 다시 적용된다.

## API

```
POST /issue?couponId=1&memberId=100

200  ISSUED
409  SOLD_OUT      재고 소진
409  DUPLICATED    1인 1매 한도 위반
404  NOT_FOUND     쿠폰 없음
```

응답 본문은 평문이다. 요청 대부분이 409라 JSON 직렬화 비용을 얹지 않는다.

---

# 테스트는 두 종류다

목적이 다르고, **조건이 서로 정반대**라 한 번에 못 본다.

| | 정합성 | 성능 |
|---|---|---|
| 답하는 질문 | 구현이 맞는가 | Redis 가 필요한가 |
| 어디서 | 각자 로컬 | EC2 2대 |
| 스크립트 | `load-test/rush.js` | `load-test/rush-remote.js` |
| 재고 | 1,000 (**마름**) | 10,000 (**마름**) |
| 회원 | 랜덤 2,000 (**겹침**) | VU 번호 (안 겹침) |
| 부하 | 2,000명 동시 1회 | 60초 램프업 → 20,000 |
| 결과 | PASS / FAIL | 숫자 비교 |

**정합성을 먼저 통과해야 성능을 잰다.** 틀린 구현은 아무리 빨라도 의미가 없고,
성능부터 재면 코드를 고친 뒤 다시 재야 한다.

---

# 1단계 · 정합성 (각자 로컬)

## 왜 로컬인가

경쟁 상태는 규모가 아니라 **겹침**에서 나온다. 커넥션 풀 50개는 VU 2,000이면
이미 고갈된다. VU 20,000이 필요 없으므로 6명이 각자 노트북에서 동시에 끝낼 수 있다.

## 왜 2,000명이 한꺼번에 몰리는가

램프업을 쓰면 재고 1,000장이 VU 100 수준에서 말라버린다. 초과 발급은
**마지막 1장을 여러 명이 동시에 노리는 순간**에만 일어나는데, 그 경계를
저부하에서 지나면 버그가 있어도 드러나지 않는다.

회원을 2,000명 풀에서 랜덤으로 뽑으므로 약 500명은 요청이 겹친다.
그 겹침이 **같은 사람이 응답 오기 전에 두 번 누르는** 상황을 만든다.

## 절차

```bash
# 1. 초기화 — 빠뜨리면 이전 결과가 섞인다
docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/reset.sql"
docker compose exec -T redis redis-cli FLUSHALL
docker compose exec -T redis redis-cli SET coupon:stock:1 1000      # Redis 브랜치만

# 2. 부하
k6 run load-test/rush.js

# 3. 판정
docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"
docker compose exec -T redis redis-cli GET coupon:stock:1           # Redis 브랜치만
docker compose exec -T redis redis-cli SCARD coupon:issued:1        # redis-watch
docker compose exec -T redis redis-cli SCARD coupon:issued-members:1 # redis-lua
```

SQL 을 컨테이너 안에서 `source` 로 실행하므로 셸 리다이렉션이 없다.
bash, zsh, PowerShell, cmd 어디서든 같은 명령을 쓴다.

## 판정

`verify.sql` 이 PASS/FAIL 로 찍어준다.

```
stock  counter  issued_rows  dup_members  oversell  counter_ok  duplicate  redis_expect
1000   1000     1000         0            PASS      PASS        PASS       0
```

| 항목 | 기준 | 의미 |
|---|---|---|
| `oversell` | PASS | 발급 행 수가 재고를 넘지 않음 |
| `duplicate` | PASS | 한 회원이 2장 받지 않음 |
| `counter_ok` | PASS 또는 N/A | 롤백·보상이 어긋나지 않음. Redis 브랜치는 카운터를 안 써서 N/A |
| `redis_expect` | `GET` 과 일치 | 보상 로직이 재고를 되돌렸음 |
| `SCARD` | `issued_rows` 와 일치 | 받지도 못했는데 등록된 회원이 없음 |
| 에러 | k6 `errors` 0 | 5xx 없음 |

동시성 버그는 확률적이라 **한 번으로는 놓친다.** 여러 번 돌려 매번 확인한다.
런당 2초면 끝난다.

## Redis 브랜치가 추가로 봐야 하는 것

Redis 와 DB 두 곳에 나눠 쓰므로 **원자성이 없다.**

```
① Redis 재고 -1, 회원 명단에 추가
② DB INSERT          ← 여기서 실패하면?
③ compensate         ← ①을 되돌려야 한다
```

③이 없으면 재고가 증발하고, 더 나쁘게는 **받지도 못한 회원이 Redis 명단에 남아
영원히 재발급을 못 받는다.** 위 표의 마지막 두 줄이 그걸 잡는다.

DB 단일 방식(`pessimistic`, `optimistic`, `atomic-update`, `redisson`)은
트랜잭션 하나로 끝나므로 이 문제가 없다.

---

# 2단계 · 성능 (EC2, 전원 통과 후)

## 구성

```
┌─ k6 서버 ─┐        ┌──── 앱 서버 ────┐
│    k6     │──부하──▶│ 앱 + MySQL + Redis │
└───────────┘        └────────────────────┘
```

2대로 나누는 이유는 k6 가 앱과 CPU 를 뺏지 않게 하기 위해서다.
로컬처럼 한 대에서 돌리면 처리량 수치를 믿을 수 없다.

## 세팅 (최초 1회)

```bash
# 앱 서버
sudo apt-get update && sudo apt-get install -y git \
  && git clone https://github.com/MO-COU/load-test.git \
  && bash load-test/scripts/setup-app.sh

# k6 서버 — 인자는 앱 서버의 프라이빗 IP
sudo apt-get update && sudo apt-get install -y git \
  && git clone https://github.com/MO-COU/load-test.git \
  && bash load-test/scripts/setup-k6.sh 10.0.1.20
```

`ulimit -n` 이 65535 인지 확인하려면 **재접속**해야 한다.

세팅이 홈에 만드는 스크립트들:

```
~/app.sh <브랜치>    브랜치 전환 → 빌드 → 실행
~/reset.sh [redis]   초기화. redis 인자는 lua/watch/redisson 에서
~/verify.sh          발급 수 확인
~/metrics.sh <이름>  커넥션 풀·워커 스레드 1초 단위 수집
~/dbstat.sh          InnoDB 락 통계
~/k6.sh <이름>       부하 생성 (k6 서버)
```

저장소가 아니라 홈에 두는 이유는 `git switch` 로 브랜치를 6번 갈아타도
사라지지 않게 하기 위해서다.

## 측정 절차

`<이름>` 은 자유롭게 정한다. 결과가 `~/results/<이름>.txt` 로 저장된다.

```bash
# ── 앱 서버 ──
~/app.sh exp/pessimistic-lock       # 브랜치 전환 후 앱 실행
~/reset.sh redis                    # 초기화
~/dbstat.sh                         # 측정 전 락 통계 기록
~/metrics.sh pessimistic            # 지표 수집 시작 (별도 SSH 창에서)

# ── k6 서버 ──
~/k6.sh pessimistic                 # 부하. 90초쯤 걸린다

# ── 앱 서버 ──
# metrics.sh 를 Ctrl+C 로 중단
~/verify.sh                         # 발급 수가 k6 issued 와 맞는지
~/dbstat.sh                         # 측정 후 락 통계
```

`reset.sh` 를 빼먹으면 **이전 회차 데이터가 남아 재고가 이미 0이다.** 가장 흔한 실수다.

## 부하 조건 (전 조 통일)

```
회원 20,000명 (중복 없음)
재고 10,000장
ramp-up 60s   0 → 20,000 (초당 약 333명)
```

램프업이 VU 구간을 훑고 지나가므로, 어느 지점에서 자원이 포화됐는지는
`metrics.sh` 의 초 단위 기록과 시각을 맞춰 보면 된다.

```
1755300020 hikaricp_connections_pending 78.0  tomcat_threads_busy 160.0
1755300030 hikaricp_connections_pending 150.0 tomcat_threads_busy 200.0   ← 포화
```

## 볼 지표

| 지표 | 출처 | 의미 |
|---|---|---|
| `issued` / 60초 | k6 요약 | **실제 발급 처리량** |
| `p95` | k6 요약 | 사용자 체감 |
| `hikaricp_connections_pending` | `metrics.sh` | **커넥션 풀 고갈** |
| `tomcat_threads_busy` | `metrics.sh` | **워커 스레드 포화** |
| `Innodb_row_lock_waits` | `dbstat.sh` | 락 경합이 실제로 늘었는지 |

`http_reqs`(TPS)는 쓰지 않는다. **실패한 요청도 세기 때문에** 빨리 포기하는 방식이
유리하게 나온다. 처리량은 `issued` 로 본다.

아래 두 줄이 결론의 근거다. 숫자만 있으면 "빠르더라"지만, 커넥션 풀이 꽉 차고
락 대기가 폭증한 기록이 있으면 **"DB 락은 구조적으로 못 버틴다"** 가 된다.

---

# 브랜치 작업 범위

| 대상 | 수정 |
|---|---|
| `CouponIssueService` | **여기만 바꾼다** |
| `CouponRepository` | 메서드 추가 가능 (`@Lock`, 조건부 `@Query`) |
| `Coupon` | 낙관적 락 브랜치만 `@Version` 추가 (컬럼은 이미 있다) |
| `build.gradle` | 의존성 추가 가능 |
| `CouponIssueController` | 금지 — k6 스크립트와의 계약 |
| `schema.sql`, `application.yaml`, `rush.js`, `rush-remote.js`, `docker-compose.yml` | 금지 — 통일 사항 |

## 통일 조건

`application.yaml` 에 있고, 임의로 바꾸면 비교가 성립하지 않는다.

```
커넥션 풀        50      기본값 10 이면 모든 방식이 "커넥션 부족"이라는
                        같은 병목에 걸려 락 전략 차이가 묻힌다
워커 스레드      200
max-connections  30,000  기본값 8192 로는 VU 20,000 의 연결을 못 받아
                        초과분이 거부되고, 락과 무관한 에러가 결과를 오염시킨다
재시도           5회 + 5~19ms 랜덤 백오프   (optimistic, redis-watch)
```

`max-connections` 30,000은 **실무 권장값이 아니라 측정용**이다. 측정 대상이 아닌
자원은 병목이 되지 않게 크게 잡고, 재고 싶은 커넥션 풀·워커 스레드만 기본값으로 둔다.

### 재시도 정책 (`optimistic`, `redis-watch`)

두 방식은 같은 낙관적 계열이라 **정책이 같아야 비교가 성립한다.**

```java
5회까지 재시도
실패할 때마다 Thread.sleep(5 + ThreadLocalRandom.current().nextInt(15));  // 5~19ms
```

백오프를 랜덤으로 두는 이유: 모두가 정확히 같은 시간을 기다리면 **그 시점에 또 다 같이
몰린다.** 무작위로 흩어져야 순간 경합자 수가 줄어든다.

### Redis 방식 주의 (`redis-lua`, `redis-watch`)

재고 판정을 Redis 가 하므로 **`coupon.issued_count` 를 갱신하지 않는다.**

```sql
UPDATE coupon SET issued_count = issued_count + 1 WHERE id = 1
```

모든 요청이 같은 행을 UPDATE 하면 InnoDB 가 그 행에 락을 걸고 커밋까지 유지한다.
Redis 에서 원자적으로 판정해놓고 DB 에서 다시 한 줄로 서게 되어, Redis 의 이점이 사라진다.

`coupon_issue` INSERT 는 남긴다. 발급 이력은 디스크에 남아야 하고,
회원마다 다른 행이라 경합하지 않는다.

`redisson-rlock` 은 락만 Redis 이고 데이터는 DB 이므로 **카운터를 그대로 쓴다.**

---

# 구조

```
scripts/db/schema.sql   테이블 (최초 1회 자동)
scripts/db/data.sql     시드 (최초 1회 자동)
scripts/db/reset.sql    매 테스트 전 초기화
scripts/db/verify.sql   정합성 판정 (PASS/FAIL)
scripts/setup-app.sh    앱 서버 세팅
scripts/setup-k6.sh     k6 서버 세팅
load-test/rush.js       정합성용 (로컬)
load-test/rush-remote.js 성능용 (EC2)
```

`coupon` 은 `total_quantity`(고정) + `issued_count`(초기화 대상) 모델이다.
재고를 바꿔도 `reset.sql` 은 수정할 필요가 없다.

`coupon_issue` 에는 `(coupon_id, member_id)` UNIQUE 인덱스가 있다.
member 테이블과 FK 는 두지 않는다 — FK 가 있으면 INSERT 마다 부모 행에
shared lock 이 걸려 락 전략 차이와 뒤섞인다.
