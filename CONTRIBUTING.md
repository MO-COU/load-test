# 작업 가이드

6가지 방식을 같은 조건에서 비교하기 위한 규칙과 절차다.
조건이 하나라도 다르면 수치를 나란히 놓을 수 없으므로 구현 전에 읽는다.

## 준비

- JDK 21 / Docker / [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/)

```bash
docker compose up -d
docker compose ps          # mysql, redis 모두 healthy 확인
./gradlew bootRun          # Windows: .\gradlew.bat bootRun
```

스키마와 시드는 컨테이너가 처음 뜰 때 자동 적용된다.
스키마를 바꿨다면 `docker compose down -v` 로 볼륨까지 지워야 다시 적용된다.

## 브랜치

```
main         동시성 제어 없는 baseline
exp/*        각 방식. main 에서 갈라져 나온다
```

`main` 에 측정 조건이 바뀌면 각자 브랜치에서 받아간다.

```bash
git fetch origin
git merge origin/main
```

`git checkout --` 은 쓰지 않는다. 브랜치 고유 의존성이 날아간다.

## 작업 범위

| 대상 | 수정 |
|---|---|
| `CouponIssueService` | **여기만 바꾼다** |
| `CouponRepository` | 메서드 추가 가능 (`@Lock`, 조건부 `@Query`) |
| `Coupon` | 낙관적 락 계열만 `@Version` 추가 (컬럼은 이미 있다) |
| `build.gradle` | 의존성 추가 가능 |
| `CouponIssueController` | 금지 — k6 스크립트와의 계약 |
| `CouponIssueConcurrencyTest` | 금지 — Redis 전용 단언만 추가 가능 |
| `schema.sql`, `application.yaml`, `rush-remote.js`, `docker-compose.yml` | 금지 |

컨트롤러를 바꾸면 부하 스크립트가 응답을 다르게 해석하고,
설정을 바꾸면 자원 조건이 달라져 다른 방식과 비교할 수 없게 된다.

### API 계약

k6 스크립트가 이 응답 코드로 발급·품절·중복을 집계한다. 바꾸면 집계가 어긋난다.

```
POST /issue?couponId=1&memberId=100

200  ISSUED
409  SOLD_OUT      재고 소진
409  DUPLICATED    1인 1매 한도 위반
404  NOT_FOUND     쿠폰 없음
```

응답 본문은 평문이다. 요청 대부분이 409 라 JSON 직렬화 비용을 얹지 않는다.

## 통일 조건

`application.yaml` 에 있다. 임의로 바꾸면 비교가 성립하지 않는다.

```
커넥션 풀        50
워커 스레드      200
max-connections  30,000   측정용 값이다. 실무 권장값이 아니다
```

`max-connections` 를 크게 잡은 이유는 이 자원이 병목이 되면 락 전략의 차이가
묻히기 때문이다. 기본값 8,192 로는 VU 20,000 의 연결을 다 받지 못해
락과 무관한 에러가 결과를 오염시킨다.

### 재시도 정책 — `optimistic`, `redis-watch`

둘 다 낙관적 계열이라 정책이 같아야 서로 비교된다.

```java
5회까지 재시도
실패할 때마다 Thread.sleep(5 + ThreadLocalRandom.current().nextInt(15));  // 5~19ms
```

백오프를 랜덤으로 두는 이유는, 모두가 정확히 같은 시간을 기다리면
그 시점에 또 다 같이 몰리기 때문이다.

### 재고를 Redis 가 관리하는 방식 — `redis-lua`, `redis-watch`

`coupon.issued_count` 를 갱신하지 않는다. 모든 요청이 같은 행을 UPDATE 하면
직렬화되어 인메모리 판정의 이점이 사라진다.

`coupon_issue` INSERT 는 남긴다. 회원마다 다른 행이라 경합하지 않는다.

`redisson-rlock` 은 락만 Redis 이고 데이터는 DB 에 있으므로 카운터를 그대로 쓴다.

## 1단계 · 정합성 검증

성능을 재기 전에 통과해야 한다. 틀린 구현은 아무리 빨라도 의미가 없고,
성능부터 재면 코드를 고친 뒤 다시 재야 한다.

```bash
docker compose up -d
./gradlew test
```

`CouponIssueConcurrencyTest` 가 두 가지를 본다.

| 테스트 | 방식 | 확인 |
|---|---|---|
| 초과 발급 | 회원 2,000명이 재고 1,000장에 동시 요청 | `coupon_issue` 행 수 == 재고 |
| 중복 발급 | 같은 회원으로 100개 스레드가 동시 출발 | 그 회원의 행 수 == 1 |

HTTP 를 거치지 않고 서비스를 스레드로 직접 호출한다. 소켓·OS·Tomcat 계층이
결과에 섞이지 않고, 2,000번 호출하면 2,000번 다 실행되기 때문이다.
DB 는 진짜를 쓴다 — 검증 대상이 행 락·UNIQUE 제약·Redis 원자성이라
모킹하면 확인할 것이 남지 않는다.

`optimistic`, `redis-watch` 는 경합에서 밀리면 서버가 5회 만에 포기하고 5xx 를 낸다.
포기는 초과 발급이 아니라 "못 준" 것이므로 정합성 위반으로 보지 않는다.
테스트가 사용자처럼 재호출해 재고가 끝까지 소진되는지 확인하고,
포기 횟수는 출력의 `서버 포기 N회` 로 남는다.

`main` 은 baseline 이라 이 테스트가 실패한다. 정상이다.

### DB 상태 확인

```bash
docker compose exec -T mysql mysql -t -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"
```

| 컬럼 | 의미 |
|---|---|
| `oversell` | 발급 행 수가 재고를 넘지 않았는가 |
| `counter_ok` | 카운터와 실제 행 수가 같은가. **테스트가 단언하지 않는 유일한 항목.** Redis 방식은 카운터를 안 써 N/A |
| `duplicate` | 한 회원이 2장 받지 않았는가 |
| `redis_expect` | Redis 재고의 기대값. `redis-lua`, `redis-watch` 만 아래와 대조 |

```bash
docker compose exec -T redis redis-cli GET coupon:stock:1
```

### Redis 방식의 추가 단언

두 저장소에 나눠 쓰므로 DB INSERT 가 실패하면 Redis 차감을 직접 되돌려야 한다.
보상이 빠지면 아무도 받지 못한 재고가 사라지고, 받지 못한 회원이 발급자 명단에
남아 재발급도 막힌다. `redis-lua`, `redis-watch` 의 테스트에는 이 단언이 들어 있다.

```java
assertThat(redisTemplate.opsForValue().get(stockKey)).isEqualTo("0");
assertThat(redisTemplate.opsForSet().size(issuedKey)).isEqualTo((long) STOCK);
```

## 2단계 · 성능 측정

로컬에서는 k6·앱·MySQL·Redis 가 CPU 를 나눠 써 처리량을 믿을 수 없다.
**EC2 2대 구성**에서 잰다.

```
┌──────────────┐               ┌───────────────────────┐
│  k6 server   │  ---load--->  │  app + MySQL + Redis  │
└──────────────┘               └───────────────────────┘
```

### 세팅 (최초 1회)

```bash
# 앱 서버
sudo apt-get update && sudo apt-get install -y git \
  && git clone https://github.com/MO-COU/load-test.git \
  && bash load-test/scripts/setup-app.sh

# k6 서버 — 인자는 앱 서버의 프라이빗 IP
sudo apt-get update && sudo apt-get install -y git \
  && git clone https://github.com/MO-COU/load-test.git \
  && bash load-test/scripts/setup-k6.sh <앱서버-프라이빗-IP>
```

`ulimit -n` 이 65535 인지 확인하려면 **재접속**해야 한다.

세팅이 홈에 만드는 스크립트들:

```
~/app.sh <브랜치>    브랜치 전환 → 빌드 → 실행
~/reset.sh [redis]   초기화. redis 인자는 lua/watch 만 (redisson 은 인자 없이)
~/verify.sh          발급 수 확인
~/metrics.sh <이름>  커넥션 풀·워커 스레드 1초 단위 수집
~/dbstat.sh          InnoDB 락 통계
~/k6.sh <이름>       부하 생성 (k6 서버)
```

`git switch` 때 사라지지 않도록 저장소가 아닌 홈에 만든다.

### 측정 절차

`<이름>` 은 자유롭게 정한다. 결과가 `~/results/<이름>.txt` 로 저장된다.

```bash
# ── 앱 서버 ──
~/app.sh exp/pessimistic-lock
~/reset.sh                          # 초기화
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

### 부하 조건

```
회원 20,000명 (중복 없음)
재고 10,000장
ramp-up 60s   0 → 20,000 (초당 약 333명)
```

### 볼 지표

| 지표 | 출처 | 의미 |
|---|---|---|
| `issued` / 60초 | k6 요약 | **실제 발급 처리량** |
| `p95` | k6 요약 | 사용자 체감 |
| `hikaricp_connections_pending` | `metrics.sh` | **커넥션 풀 고갈** |
| `tomcat_threads_busy` | `metrics.sh` | **워커 스레드 포화** |
| `Innodb_row_lock_waits` | `dbstat.sh` | 락 경합이 실제로 늘었는지 |

`http_reqs`(TPS)는 쓰지 않는다. 실패한 요청도 세기 때문에 빨리 포기하는 방식이
유리하게 나온다. 처리량은 `issued` 로 본다.

어느 지점에서 자원이 포화됐는지는 `metrics.sh` 의 초 단위 기록에서 본다.

```
1755300020 hikaricp_connections_pending 78.0  tomcat_threads_busy 160.0
1755300030 hikaricp_connections_pending 150.0 tomcat_threads_busy 200.0   ← 포화
```

## 결과 기록

`docs/results.md` 에 기존 방식과 같은 형식으로 남긴다.
k6 요약, `dbstat` 전후 차이, `metrics` 포화 지점, `verify` 판정을 함께 적는다.

## 커밋

```
브랜치   exp/<방식이름>
커밋     feat: / fix: / chore: / test: / docs:
```

통일 조건이나 공통 파일을 바꿔야 한다면 먼저 팀에 알린다.
기존 결과 전체가 무효가 되기 때문이다.
