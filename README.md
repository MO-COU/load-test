# 선착순 쿠폰 발급 방식 비교

같은 요구사항을 6가지 동시성 제어 방식으로 구현하고 동일 조건에서 비교한다.
`main`은 동시성 제어를 하지 않는 baseline이며, 각 방식은 `exp/*` 브랜치에서 구현한다.

## 사전 준비

- JDK 21
- Docker
- [k6](https://grafana.com/docs/k6/latest/set-up/install-k6/)

## 실행

```bash
docker compose up -d
docker compose ps          # mysql, redis 모두 healthy 확인

./gradlew bootRun          # Windows(PowerShell/cmd): .\gradlew.bat bootRun
```

스키마와 시드는 컨테이너가 처음 뜰 때 자동으로 적용된다.

> **스키마를 바꿨다면** `docker compose down -v` 로 볼륨까지 지워야 다시 적용된다.
> `-v` 없이 재기동하면 예전 스키마로 계속 돈다.

## 대용량 DB 실험 환경

기존 동시성 실험 DB(`3306`, `coupon`)와 분리된 MySQL을 사용한다.
대용량 DB는 `3307`, `coupon_large`, `coupon-mysql-large`, `mysql-large-data`를 사용하므로
기존 실험의 컨테이너와 데이터에 영향을 주지 않는다.

```bash
docker compose -f docker-compose.large-db.yml up -d
./gradlew bootRun --args='--spring.profiles.active=large-db'
```

Windows PowerShell에서는 `./gradlew` 대신 `./gradlew.bat`을 사용한다.
대용량 실험을 끝내고 데이터 볼륨까지 제거하려면 다음 명령을 사용한다.

```bash
docker compose -f docker-compose.large-db.yml down -v
```

## API

```
POST /issue?couponId=1&memberId=100

200  ISSUED
409  SOLD_OUT      재고 소진
409  DUPLICATED    1인 1매 한도 위반
404  NOT_FOUND     쿠폰 없음
```

응답 본문은 평문이다. 요청 대부분이 409라 JSON 직렬화 비용을 얹지 않기 위함이다.

## 테스트 절차

매번 이 순서를 지킨다. **초기화를 빠뜨리면 이전 결과가 섞인다.**

```
# 1. 초기화
docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/reset.sql"
docker compose exec redis redis-cli FLUSHALL

# Redis 방식 브랜치만 추가
docker compose exec redis redis-cli SET coupon:stock:1 1000

# 2. 부하테스트
k6 run load-test/rush.js

# 3. 결과 확인
docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"
```

SQL 파일을 컨테이너 안에서 `source` 로 실행하므로 셸 리다이렉션이 필요 없다.
bash, zsh, PowerShell, cmd 어디서든 같은 명령을 쓴다.

`issued_count`(카운터)와 `issued_rows`(실제 행)가 다르면 그 자체가 발견이다. 반드시 기록한다.

## 판정 기준

| 항목 | 기준 |
|---|---|
| 초과 발급 | 발급 건수 = 재고 |
| 중복 발급 | 회원별 발급 건수 ≤ 1 |
| 에러 | 5xx 0건 (k6 `errors` 카운터) |

baseline은 통과하지 못하는 것이 정상이다. 비교 기준점으로 결과를 기록한다.

## 브랜치 작업 범위

| 대상 | 수정 |
|---|---|
| `CouponIssueService` | **여기만 바꾼다** |
| `CouponRepository` | 메서드 추가 가능 (`@Lock`, 조건부 `@Query`) |
| `Coupon` | 낙관적 락 브랜치만 `@Version` 추가 (컬럼은 이미 있다) |
| `build.gradle` | 의존성 추가 가능 |
| `CouponIssueController` | 금지 — k6 스크립트와의 계약 |
| `schema.sql`, `application.yaml`, `rush.js`, `docker-compose.yml` | 금지 — 통일 사항 |

### Redis 방식 주의

`DECR`로 재고를 깎은 뒤 DB INSERT가 UNIQUE 제약에 걸리면 **DB는 롤백되지만 Redis 카운터는 복구되지 않는다.** 직접 되돌려야 한다. DB 방식은 트랜잭션이 처리하므로 이 문제가 없다.

## 구조

```
scripts/db/schema.sql   테이블 (최초 1회 자동 실행)
scripts/db/data.sql     시드 (최초 1회 자동 실행)
scripts/db/reset.sql    매 테스트 전 초기화
scripts/db/verify.sql   테스트 후 결과 확인
load-test/rush.js       k6 스크립트
```

`coupon` 테이블은 `total_quantity`(고정) + `issued_count`(초기화 대상) 모델이다.
재고를 바꿔도 `reset.sql`은 수정할 필요가 없다.

`coupon_issue`에는 `(coupon_id, member_id)` UNIQUE 인덱스가 있다.
member 테이블과 FK는 두지 않는다 — FK가 있으면 INSERT마다 부모 행에 shared lock이 걸려
락 전략 차이와 뒤섞이기 때문이다.

## 측정값 비교 시 주의

부하 생성기(k6)와 애플리케이션이 같은 머신에서 돈다.
**머신이 다른 팀원끼리 처리량(req/s) 절대값을 비교하면 의미가 없다.**
절대값 비교가 필요하면 한 사람 머신에서 6개 브랜치를 모두 돌린다.
