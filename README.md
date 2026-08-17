# 선착순 쿠폰 발급 방식 비교

같은 요구사항을 6가지 동시성 제어 방식으로 구현하고, 동일 조건에서 비교한다.
`main`은 동시성 제어가 없는 baseline이며 각 방식은 `exp/*` 브랜치에 있다.

## 무엇을 밝히려는가

DB 락으로 정합성을 지키면 락 경합 때문에 커넥션 풀과 워커 스레드가 고갈된다.
재고 판정을 Redis 로 옮기면 그 자원을 얼마나 확보할 수 있는가.

## 6가지 방식

동시성 제어 방법은 셋뿐이고, 각각을 DB 와 Redis 로 구현한 3쌍이다.

| 전략 | DB | Redis |
|---|---|---|
| **대기** 락을 걸고 시작 | `pessimistic-lock` | `redisson-rlock` |
| **재시도** 충돌하면 다시 | `optimistic` | `redis-watch` |
| **원자적** 한 번에 처리 | `atomic-update` | `redis-lua` |

재시도 정책이 필요한 건 가운데 줄뿐이다.

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
| 방법 | `./gradlew test` | `load-test/rush-remote.js` |
| 재고 | 1,000 | 10,000 |
| 회원 | 2,000명 (테스트가 지정) | 20,000명 (= VU 수) |
| 부하 | 스레드 100개 동시 | 60초 램프업 → 20,000 |
| 결과 | PASS / FAIL | 숫자 비교 |

**정합성을 먼저 통과해야 성능을 잰다.**

---

# 1단계 · 정합성 (각자 로컬)

```bash
docker compose up -d
./gradlew test          # Windows: .\gradlew.bat test
```

`CouponIssueConcurrencyTest` 가 두 가지를 검증한다.

| 테스트 | 방식 | 확인 |
|---|---|---|
| 초과 발급 | 회원 2,000명이 재고 1,000장에 동시 요청 | `coupon_issue` 행 수 == 재고 |
| 중복 발급 | 같은 회원으로 100개 스레드가 동시 출발 | 그 회원의 행 수 == 1 |

`main` 은 baseline 이라 실패한다. 정상이다.

## Redis 브랜치가 추가로 봐야 하는 것

DB INSERT 가 실패했을 때 Redis 예약을 되돌리지 않으면 재고가 증발하고,
받지도 못한 회원이 명단에 남아 재발급을 못 받는다.

공통 테스트는 DB 사실만 단언하므로 이건 안 본다. `redis-lua`, `redis-watch` 는
자기 브랜치에 아래를 추가한다.

```java
assertThat(redisTemplate.opsForValue().get(stockKey)).isEqualTo("0");
assertThat(redisTemplate.opsForSet().size(issuedKey)).isEqualTo((long) STOCK);
```

키 이름이 다르다 — `redis-lua` 는 `coupon:issued-members:1`, `redis-watch` 는 `coupon:issued:1`.

DB 단일 방식(`pessimistic`, `optimistic`, `atomic-update`, `redisson`)은
트랜잭션 하나로 끝나므로 해당 없다.

---

# 2단계 · 성능 (EC2, 전원 통과 후)

## 구성

```
┌──────────────┐               ┌───────────────────────┐
│  k6 server   │  ---load--->  │  app + MySQL + Redis  │
└──────────────┘               └───────────────────────┘
```

k6 와 앱이 CPU 를 나눠 쓰면 처리량 수치를 믿을 수 없어 2대로 나눈다.

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

`git switch` 때 사라지지 않도록 저장소가 아닌 홈에 만든다.

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

어느 지점에서 자원이 포화됐는지는 `metrics.sh` 의 초 단위 기록에서 본다.

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

---

# 브랜치 작업 범위

| 대상 | 수정 |
|---|---|
| `CouponIssueService` | **여기만 바꾼다** |
| `CouponRepository` | 메서드 추가 가능 (`@Lock`, 조건부 `@Query`) |
| `Coupon` | 낙관적 락 브랜치만 `@Version` 추가 (컬럼은 이미 있다) |
| `build.gradle` | 의존성 추가 가능 |
| `CouponIssueController` | 금지 — k6 스크립트와의 계약 |
| `CouponIssueConcurrencyTest` | 금지 — 통일 사항. Redis 전용 단언만 추가 가능 |
| `schema.sql`, `application.yaml`, `rush-remote.js`, `docker-compose.yml` | 금지 — 통일 사항 |

## 통일 조건

`application.yaml` 에 있고, 임의로 바꾸면 비교가 성립하지 않는다.

```
커넥션 풀        50
워커 스레드      200
max-connections  30,000   측정용 값이다. 실무 권장값이 아니다
재시도           5회 + 5~19ms 랜덤 백오프   (optimistic, redis-watch)
```

### 재시도 정책 (`optimistic`, `redis-watch`)

두 방식은 같은 낙관적 계열이라 **정책이 같아야 비교가 성립한다.**

```java
5회까지 재시도
실패할 때마다 Thread.sleep(5 + ThreadLocalRandom.current().nextInt(15));  // 5~19ms
```

### Redis 방식 주의 (`redis-lua`, `redis-watch`)

재고 판정을 Redis 가 하므로 **`coupon.issued_count` 를 갱신하지 않는다.**
모든 요청이 같은 행을 UPDATE 해 직렬화되면 Redis 의 이점이 사라진다.

`coupon_issue` INSERT 는 남긴다. 회원마다 다른 행이라 경합하지 않는다.

`redisson-rlock` 은 락만 Redis 이므로 **카운터를 그대로 쓴다.**

---

# 구조

```
scripts/db/schema.sql   테이블 (최초 1회 자동)
scripts/db/data.sql     시드 (최초 1회 자동)
scripts/db/reset.sql    EC2 측정 전 초기화
scripts/db/verify.sql   EC2 측정 후 발급 수 확인
scripts/setup-app.sh    앱 서버 세팅
scripts/setup-k6.sh     k6 서버 세팅
load-test/rush-remote.js  성능용 (EC2)
src/test/.../CouponIssueConcurrencyTest.java  정합성용 (로컬)
```

`data.sql` 은 `coupon_id=1` 행을 존재하게 만드는 것이 목적이다. 재고 값 자체는
기본값일 뿐이고, JUnit 은 `@BeforeEach` 가, EC2 는 `~/reset.sh` 가 각자 덮어쓴다.

`coupon_issue` 에는 `(coupon_id, member_id)` UNIQUE 인덱스가 있다.
member 테이블과 FK 는 두지 않는다 — FK 가 있으면 INSERT 마다 부모 행에
shared lock 이 걸려 락 전략 차이와 뒤섞인다.
