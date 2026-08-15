# 조회 인덱스 최적화 Stage 1 측정 결과

비교 대상: [Baseline Stage 1](../baseline/stage-1.md)

데이터: MEMBER 100,000 / COUPON_ISSUE 300,000

적용 인덱스: `idx_coupon_issue_member_issued_at (member_id, issued_at DESC)`

## 조회 결과

`MEMBER_COUNT=100000`, 30초, 오류율 0%.

| VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 | 총 요청 수 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 56.94ms | 3.92ms | 63.59ms | 4.86ms | 17.51 req/s | 249.83 req/s | 7,495 |
| 10 | 102.45ms | 5.79ms | 153.22ms | 6.66ms | 97.33 req/s | 1,697.23 req/s | 50,924 |
| 50 | 439.49ms | 18.23ms | 646.26ms | 25.76ms | 113.22 req/s | 2,714.72 req/s | 81,463 |

| VU | Avg 감소 | p95 감소 | 처리량 증가 |
| --- | ---: | ---: | ---: |
| 1 | 93.12% | 92.36% | 14.27x |
| 10 | 94.35% | 95.65% | 17.44x |
| 50 | 95.85% | 96.01% | 23.98x |

## 조회 실행계획

대표 회원 ID `50000`에서 MySQL은 `idx_coupon_issue_member_issued_at`를 사용해 3건을 조회했다.

```text
Index lookup on coupon_issue using idx_coupon_issue_member_issued_at
(member_id=50000), actual time=0.025..0.0263ms, rows=3
```

## INSERT·UPDATE·집계 결과

오류율은 모든 측정에서 0%다. INSERT와 UPDATE는 VU당 1,000회를 실행했다.

| 기능 | VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| INSERT | 1 | 8.49ms | 8.42ms | 10.57ms | 10.86ms | 115.86 req/s | 116.98 req/s |
| INSERT | 10 | 14.07ms | 14.32ms | 19.09ms | 19.55ms | 700.68 req/s | 686.73 req/s |
| INSERT | 50 | 23.93ms | 24.29ms | 31.25ms | 34.88ms | 2,053.08 req/s | 2,021.35 req/s |
| UPDATE | 1 | 9.01ms | 8.41ms | 12.11ms | 11.24ms | 108.93 req/s | 116.71 req/s |
| UPDATE | 10 | 13.96ms | 13.42ms | 19.14ms | 18.37ms | 703.55 req/s | 732.15 req/s |
| UPDATE | 50 | 20.98ms | 23.81ms | 27.23ms | 31.89ms | 2,337.73 req/s | 2,065.36 req/s |
| 집계 | 1 | 137.88ms | 159.35ms | 159.49ms | 181.66ms | 7.25 req/s | 6.27 req/s |
| 집계 | 10 | 235.21ms | 264.41ms | 256.80ms | 297.65ms | 42.36 req/s | 37.70 req/s |
| 집계 | 50 | 1.14s | 1.23s | 1.40s | 1.64s | 43.30 req/s | 40.40 req/s |

조회 인덱스는 집계의 `coupon_id, status` 그룹화에는 사용되지 않으므로, 집계 성능 개선을 기대하는 대상이 아니다.
