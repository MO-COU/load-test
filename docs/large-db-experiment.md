# 대용량 DB 성능 실험 기준

## 목적

이 실험은 **쿠폰 발급 이력(`COUPON_ISSUE`)이 증가할 때, 자주 사용할 조회·집계 쿼리가
언제 느려지고 왜 느려지는지 확인하는 사전 검증**이다.

현재 목적은 전체 쿠폰 발급 서비스를 최종적으로 검증하는 것이 아니라, 확정 전 MVP ERD에
공통으로 남을 핵심 테이블의 조회 구조를 미리 안전하게 만드는 것이다. 데이터 증가에 따른
성능 저하를 수치와 실행계획으로 확인하고, 인덱스 또는 쿼리 개선 전후를 같은 조건에서 비교한다.

### 이 실험이 답하는 질문

- 발급 이력이 30만 건에서 300만 건으로 늘면 회원별 쿠폰 조회와 상태별 집계는 얼마나 느려지는가?
- 어느 동시성 구간에서 처리량 증가가 멈추고 p95 지연시간이 급격히 증가하는가?
- 느려진 원인은 Full Table Scan, 정렬, 임시 테이블 집계 중 무엇인가?
- 인덱스를 적용하면 실제 rows, 실행계획, Avg, p95가 어떻게 달라지는가?

### 현재 실험의 범위와 제외 범위

| 구분 | 현재 대용량 실험 | MVP ERD 확정 후 심화 실험 |
| --- | --- | --- |
| 회원별 쿠폰 조회 | `coupon_issue` 조회와 인덱스 개선 | 확정 컬럼 기준 API·응답 형태 재검증 |
| 쿠폰·상태별 집계 | 전체 이력 집계의 증가 추이와 개선 | 운영 통계 구조·캐시·집계 테이블 필요성 검토 |
| 신규 발급 | `coupon_issue` INSERT 성능 | `coupon_stock` 차감 + 발급 + 이력 저장 트랜잭션 |
| 상태 변경 | `ISSUED → USED` UPDATE 성능 | `used_at`·`updated_at` 갱신, 이력·멱등성 처리 포함 |
| 만료 Batch | 현재 범위에서 제외 | `expires_at` 기반 대상 조회와 Chunk Size별 처리량·DB 부하 측정 |
| 동시 발급 경합 | 현재 범위에서 제외 | 동일 쿠폰 재고 행 잠금, 클라우드 20,000 VU 부하 측정 |

현재 INSERT와 UPDATE 결과는 단일 테이블 기준의 기초 성능으로 해석한다. 실제 발급 트랜잭션의
재고 잠금, 상태 이력 INSERT, 멱등성 제약 비용까지 대표하는 결과는 아니다.

## 데이터 규모

회원 수와 발급 이력 수의 비율은 `1 : 3`으로 고정한다.

| 단계 | MEMBER | COUPON_ISSUE |
| --- | ---: | ---: |
| Stage 1 | 100,000 | 300,000 |
| Stage 2 | 300,000 | 900,000 |
| Stage 3 | 500,000 | 1,500,000 |
| Stage 4 | 1,000,000 | 3,000,000 |

## 환경 원칙

- 기존 동시성 실험 DB와 대용량 실험 DB를 분리한다.
- 대용량 DB는 별도 Docker MySQL 컨테이너, 포트, 데이터베이스명, 볼륨을 사용한다.
- 애플리케이션은 대용량 실험 전용 프로필로만 이 DB에 접속한다.
- MySQL 버전, 애플리케이션 설정, 커넥션 풀, 부하 조건은 단계 간 바꾸지 않는다.
- 로컬 결과는 절대 성능 수치가 아니라 동일 머신·동일 조건에서의 단계별 및 개선 전후 비교로 해석한다.

## 대표 기능

1. 조회: 회원별 쿠폰 조회
2. INSERT: 신규 발급 이력 저장
3. UPDATE: 쿠폰 상태 `ISSUED`에서 `USED`로 변경
4. 집계: 쿠폰별·상태별 발급 건수
5. Spring Batch: 만료 대상 대량 처리(ERD 확정 후 심화 실험)

`member` 테이블과 `coupon_issue.status` 컬럼은 위 기능을 위해 대용량 실험 전용 스키마에 포함한다.

## 실험 절차

### 1. Baseline 준비

- PK와 무결성 보장에 필요한 인덱스만 둔 스키마로 시작한다.
- 성능 개선 목적의 인덱스는 이 단계에서 추가하지 않는다.
- 각 대표 기능의 데이터 분포, 요청 수, 동시성 및 성공 기준을 기록한다.

### 1-1. 단계 데이터 준비

대용량 전용 MySQL 컨테이너가 실행 중인 상태에서 아래 명령으로 원하는 단계의
회원 수와 발급 이력(회원 수의 3배)을 재생성한다.

```bash
docker compose -f docker-compose.large-db.yml exec -T mysql-large mysql -ucoupon_large -pcoupon-large-1234 --init-command="SET @member_count = 100000" coupon_large -e "source /scripts/large-db/seed-stage.sql"
```

`@member_count` 값만 바꾸어 Stage 2~4에 사용한다. 이 스크립트는 이전 단계 데이터를
초기화한 뒤 회원별로 쿠폰 3개에 한 건씩 발급 이력을 생성한다. `ISSUED`와 `USED` 상태는
각각 절반씩 생성한다.

### 2. 단계별 측정

각 데이터 단계에서 아래 순서를 동일하게 반복한다.

1. 해당 단계의 MEMBER 및 COUPON_ISSUE 데이터를 준비한다.
2. 조회, INSERT, UPDATE, 집계의 Avg, p95, 실행시간을 기록한다.
3. 조회·집계처럼 데이터 증가에 따라 악화되는 쿼리는 `EXPLAIN ANALYZE`로 분석한다.
4. 결과와 관찰 내용을 기록한 뒤 다음 데이터 단계로 진행한다.

### 3. Baseline 완료 상태

Baseline 측정은 Stage 1~4에서 완료했다. 상세 결과는 아래 문서를 사용한다.

- [결과 문서 구조](benchmark-results/README.md)
- [Baseline Stage 1: 회원 10만 / 발급 이력 30만](benchmark-results/baseline/stage-1.md)
- [Baseline Stage 2: 회원 30만 / 발급 이력 90만](benchmark-results/baseline/stage-2.md)
- [Baseline Stage 3: 회원 50만 / 발급 이력 150만](benchmark-results/baseline/stage-3.md)
- [Baseline Stage 4: 회원 100만 / 발급 이력 300만](benchmark-results/baseline/stage-4.md)

Stage 4에서 확인된 기준선은 다음과 같다.

- 회원별 쿠폰 조회: 300만 건 Full Scan 후 정렬, 50 VU p95 `5.06s`
- 쿠폰·상태별 집계: 300만 건 Full Scan, 임시 테이블 집계·정렬, 50 VU p95 `13.11s`
- INSERT·UPDATE: 같은 조건에서 50 VU p95 약 `30ms` 수준

## 실행계획 확인 항목

느린 쿼리마다 다음을 기록한다.

- Full Table Scan 여부
- 실제 rows 및 rows 증가 양상
- 사용한 인덱스
- 실제 실행시간
- 잠금 대기 또는 경합 징후

## 개선 및 재측정

1. 최초로 기준을 넘긴 쿼리 또는 Batch 작업을 병목으로 선정한다.
2. 인덱스, 쿼리, Batch chunk 중 한 가지 가설만 적용한다.
3. 문제가 처음 나타난 단계와 Stage 4에서 같은 조건으로 다시 측정한다.
4. `EXPLAIN ANALYZE`를 다시 실행해 전후 차이를 저장한다.
5. 개선 전후에 대해 Avg, p95, 실행시간, 실제 rows, Full Scan 여부를 나란히 비교한다.

## 전체 진행 흐름

```text
1차: 현재 단순화 스키마에서 조회·집계 병목을 찾는다
  → Stage 1~4 Baseline 완료
  → 인덱스 가설을 하나씩 적용하고 Stage 4에서 재측정
  → 개선 전/후 실행계획과 p95 비교

2차: MVP ERD 확정 후 실제 발급 흐름을 반영한다
  → coupon_stock, 확장된 coupon_issue, coupon_issue_history 반영
  → 재고 차감 + 발급 + 이력 저장 트랜잭션 측정
  → expires_at 기반 Spring Batch 측정
  → 클라우드 환경에서 20,000 VU 동시 발급·잠금 경합 측정
```
