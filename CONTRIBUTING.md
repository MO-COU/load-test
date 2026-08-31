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
| `schema.sql`, `application.yaml`, `rush-spike.js`, `docker-compose.yml` | 금지 |

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
커넥션 풀        16        HikariCP 권장식 (코어 수 × 2) + 디스크 수
워커 스레드      200       Tomcat 기본값
max-connections  30,000    2만 연결을 다 받기 위한 값. 실무 권장값이 아니다
accept-count     32768     2만 개 동시 도착을 흡수. 기본값 100 으로는 연결이 버려진다
```

`accept-count` 는 OS 의 `somaxconn` 보다 크면 조용히 깎이므로 함께 올려야 한다.
`setup-app.sh` 가 `somaxconn`·`tcp_max_syn_backlog` 를 32768 로 설정한다.

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

저장소의 `scripts/db/` 가 컨테이너 안에서 `/scripts` 로 마운트돼 있다
(`docker-compose.yml` 의 `./scripts/db:/scripts:ro`). 컨테이너 안에서 `source` 로
실행하므로 셸 리다이렉션이 없고, bash·zsh·PowerShell·cmd 어디서든 같은 명령을 쓴다.

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
~/app.sh <브랜치>       브랜치 전환 → 빌드 → 백그라운드 실행
~/before.sh <이름> [redis]  초기화 + 사전 지표 + 모니터 기동
~/drain.sh              서버가 밀린 요청을 다 소화할 때까지 대기
~/after.sh <이름>       모니터 중지 + 사후 지표 + 판정
~/stop.sh               앱 중지
~/k6.sh <이름>          부하 생성 (k6 서버)
```

`redis` 인자는 `lua`·`watch` 만 붙인다. `redisson` 은 재고를 DB 에서 관리하므로
붙이면 쓰지 않는 Redis 키가 남아 재고누수 오탐이 난다.

`git switch` 때 사라지지 않도록 저장소가 아닌 홈에 만든다.

### 측정 절차

`<이름>` 은 자유롭게 정한다. 결과가 `~/results/<이름>.txt` 로 저장된다.

```bash
# ── 앱 서버 ──
~/app.sh exp/pessimistic-lock       # 브랜치 전환 → 빌드 → 백그라운드 실행
~/before.sh pess-1                  # 초기화 + 사전 지표 + 모니터 기동
                                    # Redis 재고를 쓰는 방식은:  ~/before.sh lua-1 redis

# ── k6 서버 ──
~/k6.sh pess-1                      # 부하

# ── 앱 서버 ──
~/drain.sh                          # 부하가 끝나도 서버는 밀린 요청을 처리 중이다
~/after.sh pess-1                   # 모니터 중지 + 사후 지표 + 판정 출력
```

**`drain.sh` 를 빼면 안 된다.** k6 는 요청 타임아웃 60초에서 포기하지만 서버는
그 요청들을 계속 처리한다. 바로 판정을 읽으면 처리 중인 건이 빠져 발급 수가
실제보다 적게 나오고, 그대로 다음 회차를 초기화하면 **이전 회차의 잔여 요청이
새 회차의 재고를 먹는다.** `drain.sh` 는 발급 행 수가 10초간 늘지 않을 때까지
기다린다(최대 180초).

`before.sh` 는 `metrics`(0.2초 간격)·`vmstat`·accept 큐 깊이를 동시에 수집하고,
`after.sh` 가 전후 차이와 최대값을 계산해 출력한다.

액추에이터는 관리 포트(19090)로 분리돼 있다. 메인 커넥터가 포화되면
지표 수집 요청까지 밀려 정작 포화 구간을 못 찍기 때문이다.

`before.sh` 가 초기화까지 하므로 빼먹으면 **이전 회차 재고가 그대로 0이다.** 가장 흔한 실수다.

### 부하 조건

```
회원 20,000명 (중복 없음) — 1인 1요청, 재요청 없음
재고 10,000장
동시 출발 (k6 per-vu-iterations) — 전원이 재고가 남은 상태에서 경쟁한다
요청 타임아웃 60초 (k6 기본값) — 넘기면 사용자는 결과를 받지 못한 것으로 센다
```

재요청을 하지 않는 이유는 **요청 수를 20,000 으로 고정해야 방식 간 부하가
같아지기** 때문이다. 재요청을 넣으면 느린 방식일수록 타임아웃이 많아 요청이
불어나고, 그러면 같은 조건에서 비교했다고 말할 수 없다.

### 볼 지표

| 지표 | 출처 | 의미 |
|---|---|---|
| `http_req_failed` | k6 요약 | **대표 지표.** 60초 안에 결과를 받지 못한 비율 |
| DB 발급 행 수 | `verify.sh` | **대표 지표.** 재고를 다 팔았는가 |
| 실행 시간 | k6 요약 마지막 줄 | 60초 근처면 타임아웃에 잘린 값이라 그대로 쓰지 않는다 |
| `p95` | k6 요약 | 사용자 체감. 59.9초면 잘린 값이다 |
| `hikaricp_connections_pending` | `metrics.sh` | **커넥션 풀 고갈** |
| `tomcat_threads_busy` | `metrics.sh` | **워커 스레드 포화** |
| `Innodb_row_lock_waits` | `dbstat.sh` | 락 경합이 실제로 늘었는지 |

비교는 **실패율과 DB 발급 수**로 한다. 부하가 2만 건으로 고정돼 있으므로
"2만 명 중 몇 명이 답을 받았고 재고를 다 팔았는가"가 그대로 성능이 된다.

소요 시간은 60초 타임아웃에 걸리는 방식이 많아 대표 지표로 쓰기 어렵다.
`60초+` 로만 적고 순위는 매기지 않는다.

어느 지점에서 자원이 포화됐는지는 `metrics.sh` 의 초 단위 기록에서 본다.

```
1788134812.4 hikaricp_connections_active=16.0 hikaricp_connections_pending=184.0 ...
```

브랜치당 2회 측정한다. 그룹 안 순위를 말하려면 재현성이 있어야 한다.

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
