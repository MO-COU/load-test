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

## INSERT·UPDATE·집계 결과

오류율은 모든 측정에서 0%다. INSERT와 UPDATE는 VU당 1,000회를 실행했다.

| 기능 | VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| INSERT | 1 | 9.84ms | 8.63ms | 13.33ms | 11.33ms | 100.22 req/s | 113.89 req/s |
| INSERT | 10 | 13.78ms | 20.51ms | 18.62ms | 52.98ms | 715.51 req/s | 483.06 req/s |
| INSERT | 50 | 23.97ms | 22.73ms | 32.82ms | 29.97ms | 2,049.03 req/s | 2,163.94 req/s |
| UPDATE | 1 | 8.97ms | 8.21ms | 12.19ms | 10.43ms | 109.65 req/s | 119.48 req/s |
| UPDATE | 10 | 13.38ms | 22.47ms | 17.68ms | 58.42ms | 734.77 req/s | 440.18 req/s |
| UPDATE | 50 | 24.77ms | 23.60ms | 34.08ms | 31.83ms | 1,983.57 req/s | 2,081.55 req/s |
| 집계 | 1 | 770.45ms | 459.65ms | 1.00s | 493.19ms | 1.30 req/s | 2.17 req/s |
| 집계 | 10 | 1.24s | 740.60ms | 1.37s | 763.38ms | 7.88 req/s | 13.47 req/s |
| 집계 | 50 | 6.02s | 3.57s | 7.43s | 4.46s | 8.04 req/s | 13.74 req/s |

조회 인덱스는 집계의 `coupon_id, status` 그룹화에는 사용되지 않으므로, 집계 차이는 로컬 실행 환경 변동을 포함해 해석한다.
