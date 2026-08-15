# 조회 인덱스 최적화 Stage 2 측정 결과

비교 대상: [Baseline Stage 2](../baseline/stage-2.md)

데이터: MEMBER 300,000 / COUPON_ISSUE 900,000

적용 인덱스: `idx_coupon_issue_member_issued_at (member_id, issued_at DESC)`

## 조회 결과

`MEMBER_COUNT=300000`, 30초, 오류율 0%.

| VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 | 총 요청 수 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 151.65ms | 4.12ms | 172.41ms | 5.26ms | 6.59 req/s | 237.49 req/s | 7,125 |
| 10 | 247.82ms | 5.75ms | 270.21ms | 6.70ms | 40.23 req/s | 1,710.29 req/s | 51,311 |
| 50 | 1.14s | 17.34ms | 1.38s | 23.79ms | 43.25 req/s | 2,857.75 req/s | 85,755 |

| VU | Avg 감소 | p95 감소 | 처리량 증가 |
| --- | ---: | ---: | ---: |
| 1 | 97.28% | 96.95% | 36.04x |
| 10 | 97.68% | 97.52% | 42.51x |
| 50 | 98.48% | 98.28% | 66.08x |

## 실행계획

조회는 3건 인덱스 조회, 집계는 900,000행 Full Scan 후 임시 테이블 집계·정렬로 실행됐다.

```text
조회: idx_coupon_issue_member_issued_at index lookup
(member_id=150000), actual time=0.0603..0.0625ms, rows=3

집계: Table scan on coupon_issue, actual time=0.112..149ms, rows=900000
      Aggregate using temporary table, actual time=474ms, rows=6
      Sort: coupon_id, status, actual time=474ms, rows=6
```

## INSERT·UPDATE·집계 결과

오류율은 모든 측정에서 0%다. INSERT와 UPDATE는 VU당 1,000회를 실행했다.

| 기능 | VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| INSERT | 1 | 8.75ms | 8.64ms | 11.34ms | 11.13ms | 112.47 req/s | 113.93 req/s |
| INSERT | 10 | 13.04ms | 12.96ms | 17.13ms | 17.32ms | 755.03 req/s | 756.45 req/s |
| INSERT | 50 | 23.01ms | 23.63ms | 30.23ms | 31.68ms | 2,135.17 req/s | 2,075.08 req/s |
| UPDATE | 1 | 8.54ms | 8.94ms | 11.22ms | 12.52ms | 115.18 req/s | 109.87 req/s |
| UPDATE | 10 | 13.33ms | 14.66ms | 17.50ms | 20.03ms | 739.55 req/s | 668.94 req/s |
| UPDATE | 50 | 24.60ms | 23.88ms | 33.09ms | 32.27ms | 1,997.04 req/s | 2,055.77 req/s |
| 집계 | 1 | 408.26ms | 452.40ms | 446.15ms | 494.76ms | 2.45 req/s | 2.21 req/s |
| 집계 | 10 | 720.50ms | 744.76ms | 791.64ms | 781.70ms | 13.84 req/s | 13.39 req/s |
| 집계 | 50 | 3.42s | 3.67s | 3.90s | 4.72s | 14.32 req/s | 13.34 req/s |

조회 인덱스는 집계의 `coupon_id, status` 그룹화에는 사용되지 않으므로, 집계 성능 개선을 기대하는 대상이 아니다.
