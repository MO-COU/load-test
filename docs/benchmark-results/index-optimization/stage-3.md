# 조회 인덱스 최적화 Stage 3 측정 결과

비교 대상: [Baseline Stage 3](../baseline/stage-3.md)

데이터: MEMBER 500,000 / COUPON_ISSUE 1,500,000

적용 인덱스: `idx_coupon_issue_member_issued_at (member_id, issued_at DESC)`

## 조회 결과

`MEMBER_COUNT=500000`, 30초, 오류율 0%.

| VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 | 총 요청 수 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 249.47ms | 3.89ms | 281.18ms | 4.71ms | 4.01 req/s | 251.78 req/s | 7,554 |
| 10 | 406.82ms | 5.69ms | 426.45ms | 6.69ms | 24.46 req/s | 1,723.16 req/s | 51,699 |
| 50 | 2.00s | 17.64ms | 2.33s | 24.32ms | 24.64 req/s | 2,810.97 req/s | 84,358 |

| VU | Avg 감소 | p95 감소 | 처리량 증가 |
| --- | ---: | ---: | ---: |
| 1 | 98.44% | 98.32% | 62.79x |
| 10 | 98.60% | 98.43% | 70.45x |
| 50 | 99.12% | 98.96% | 114.08x |

## 실행계획

조회는 3건 인덱스 조회, 집계는 1,500,000행 Full Scan 후 임시 테이블 집계·정렬로 실행됐다.

```text
조회: idx_coupon_issue_member_issued_at index lookup
(member_id=250000), actual time=0.0312..0.0328ms, rows=3

집계: Table scan on coupon_issue, actual time=0.0604..286ms, rows=1500000
      Aggregate using temporary table, actual time=814ms, rows=6
      Sort: coupon_id, status, actual time=814ms, rows=6
```

## INSERT·UPDATE·집계 결과

오류율은 모든 측정에서 0%다. INSERT와 UPDATE는 VU당 1,000회를 실행했다.

| 기능 | VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| INSERT | 1 | 9.84ms | 8.63ms | 13.33ms | 11.33ms | 100.22 req/s | 113.89 req/s |
| INSERT | 10 | 13.78ms | 15.25ms | 18.62ms | 21.50ms | 715.51 req/s | 646.34 req/s |
| INSERT | 50 | 23.97ms | 22.73ms | 32.82ms | 29.97ms | 2,049.03 req/s | 2,163.94 req/s |
| UPDATE | 1 | 8.97ms | 8.21ms | 12.19ms | 10.43ms | 109.65 req/s | 119.48 req/s |
| UPDATE | 10 | 13.38ms | 13.97ms | 17.68ms | 19.28ms | 734.77 req/s | 703.95 req/s |
| UPDATE | 50 | 24.77ms | 23.60ms | 34.08ms | 31.83ms | 1,983.57 req/s | 2,081.55 req/s |
| 집계 | 1 | 770.45ms | 722.69ms | 1.00s | 787.47ms | 1.30 req/s | 1.38 req/s |
| 집계 | 10 | 1.24s | 1.48s | 1.37s | 1.76s | 7.88 req/s | 6.65 req/s |
| 집계 | 50 | 6.02s | 6.33s | 7.43s | 8.38s | 8.04 req/s | 7.59 req/s |

조회 인덱스는 집계의 `coupon_id, status` 그룹화에는 사용되지 않으므로, 집계 차이는 로컬 실행 환경 변동을 포함해 해석한다.
