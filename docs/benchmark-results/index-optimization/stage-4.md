# 조회 인덱스 최적화 Stage 4 측정 결과

비교 대상: [Baseline Stage 4](../baseline/stage-4.md)

데이터: MEMBER 1,000,000 / COUPON_ISSUE 3,000,000

적용 인덱스: `idx_coupon_issue_member_issued_at (member_id, issued_at DESC)`

## 조회 결과

`MEMBER_COUNT=1000000`, 30초, 오류율 0%.

| VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 | 총 요청 수 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 649.71ms | 3.82ms | 706.32ms | 4.69ms | 1.54 req/s | 256.29 req/s | 7,689 |
| 10 | 885.42ms | 5.79ms | 990.55ms | 6.69ms | 11.20 req/s | 1,697.06 req/s | 50,914 |
| 50 | 4.44s | 19.17ms | 5.06s | 31.06ms | 11.04 req/s | 2,582.82 req/s | 77,507 |

| VU | Avg 감소 | p95 감소 | 처리량 증가 |
| --- | ---: | ---: | ---: |
| 1 | 99.41% | 99.34% | 166.42x |
| 10 | 99.35% | 99.32% | 151.52x |
| 50 | 99.57% | 99.39% | 233.95x |

## 조회 실행계획

대표 회원 ID `500000`에서 MySQL은 `idx_coupon_issue_member_issued_at`를 사용해 3건을 조회했다.

```text
Index lookup on coupon_issue using idx_coupon_issue_member_issued_at
(member_id=500000), actual time=0.0283..0.0294ms, rows=3
```

## 집계 실행계획

3,000,000행을 Full Scan한 뒤 임시 테이블로 집계하고 정렬했다. 조회 인덱스는 사용되지 않았다.

```text
Table scan on coupon_issue, actual time=0.046..651ms, rows=3000000
Aggregate using temporary table, actual time=1678ms, rows=6
Sort: coupon_id, status, actual time=1678ms, rows=6
```

## INSERT·UPDATE·집계 결과

오류율은 모든 측정에서 0%다. INSERT와 UPDATE는 VU당 1,000회를 실행했다.

| 기능 | VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| INSERT | 1 | 8.45ms | 8.48ms | 11.13ms | 10.70ms | 116.26 req/s | 116.05 req/s |
| INSERT | 10 | 13.34ms | 14.51ms | 17.68ms | 19.96ms | 738.75 req/s | 679.11 req/s |
| INSERT | 50 | 22.45ms | 23.88ms | 30.45ms | 32.22ms | 2,187.23 req/s | 2,057.56 req/s |
| UPDATE | 1 | 9.30ms | 9.03ms | 12.87ms | 12.43ms | 105.85 req/s | 108.90 req/s |
| UPDATE | 10 | 13.25ms | 14.60ms | 17.74ms | 20.04ms | 740.52 req/s | 671.05 req/s |
| UPDATE | 50 | 24.28ms | 24.07ms | 32.30ms | 32.59ms | 2,020.11 req/s | 2,039.71 req/s |
| 집계 | 1 | 1.46s | 1.56s | 1.56s | 1.67s | 0.68 req/s | 0.64 req/s |
| 집계 | 10 | 2.55s | 2.82s | 2.83s | 3.12s | 3.90 req/s | 3.48 req/s |
| 집계 | 50 | 12.22s | 13.37s | 13.11s | 15.94s | 3.99 req/s | 3.50 req/s |

조회 인덱스는 집계의 `coupon_id, status` 그룹화에는 사용되지 않으므로, 집계 차이는 로컬 실행 환경 변동을 포함해 해석한다.
