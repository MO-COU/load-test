# Baseline 쿠폰 발급 흐름

## 이 코드의 목적

이 프로젝트는 쿠폰 발급 동시성 제어 방식을 비교하기 위한 기준 구현이다. 현재 Baseline은 Spring Boot, MySQL, JPA의 기본 기능만 사용하며, 동시성 문제를 해결하지 않는다.

이후 낙관적 락, 비관적 락, DB Atomic UPDATE, Redis 방식을 이 구현과 비교한다.

## 발급 API

`POST /api/coupons/{couponId}/issue`

요청 본문에는 발급 받을 회원 식별자를 전달한다.

```json
{
  "memberId": 1
}
```

성공하면 HTTP 201과 발급 이력 정보를 반환한다.

## 도메인

- `Member`: 회원 식별자(`memberId`)를 가진다.
- `Coupon`: 쿠폰 이름과 남은 재고(`quantity`)를 가진다.
- `CouponIssue`: 어떤 회원에게 어떤 쿠폰이 언제 발급됐는지 기록한다.

## 발급 순서

Service 계층의 하나의 트랜잭션에서 다음 순서로 실행한다.

1. `memberId`로 회원을 조회한다.
2. `couponId`로 쿠폰을 조회한다.
3. 쿠폰 재고가 0 이하이면 품절 오류를 반환한다.
4. Coupon Entity의 `decreaseQuantity()`로 재고를 1 감소시킨다.
5. CouponIssue를 생성해 저장한다.
6. 발급 이력을 HTTP 응답으로 반환한다.

JPA는 트랜잭션이 끝날 때 변경된 Coupon을 Dirty Checking으로 반영하고, CouponIssue를 INSERT한다.

```text
SELECT member → SELECT coupon → quantity 확인 → quantity 1 감소
→ UPDATE coupon → INSERT coupon_issue
```

## 오류 응답

| 상황 | HTTP 상태 |
| --- | --- |
| 회원 없음 | 404 |
| 쿠폰 없음 | 404 |
| 재고 없음 | 409 |

## 의도적으로 하지 않는 것

이 단계는 동시성 문제를 해결하지 않는다. 따라서 다음을 사용하지 않는다.

- Redis, Kafka
- `@Version` 기반 낙관적 락
- 비관적 락, `SELECT FOR UPDATE`
- 조건부/Atomic UPDATE
- `synchronized`, `ReentrantLock`, 분산 락

동시에 여러 요청이 들어오면 재고 정합성 문제가 생길 수 있으며, 이것이 이후 비교 구현의 출발점이다.

## 실행 방법

로컬 MySQL 설정, 초기화, 애플리케이션 실행, API 호출 방법은 프로젝트 루트의 `README.md`를 따른다.
