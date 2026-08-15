# 조회 인덱스 최적화 Stage 4 측정 결과

비교 대상: [Baseline Stage 4](../baseline/stage-4.md)

측정 일시: 2026-08-15

데이터: MEMBER 1,000,000 / COUPON_ISSUE 3,000,000

## 가설과 적용 범위

회원별 쿠폰 조회는 `member_id` 조건을 만족하는 행을 찾은 뒤 `issued_at DESC`로 정렬한다.
`coupon_issue`에 `(member_id, issued_at DESC)` 복합 인덱스를 추가하면 전체 300만 행 스캔과
정렬 없이 회원당 3건을 인덱스 순서로 조회할 수 있다.

```sql
ALTER TABLE coupon_issue
    ADD INDEX idx_coupon_issue_member_issued_at (member_id, issued_at DESC);
```

- 스키마 반영: `scripts/large-db/schema.sql`
- 기존 Stage 4 DB 적용: `scripts/large-db/apply-read-index.sql`
- 변경하지 않은 항목: 조회 SQL, k6 스크립트, 데이터 규모, 실행 시간(30초), 애플리케이션 프로필(`large-db`)

## 조회 부하 결과

`load-test/large-db-read.js`를 `MEMBER_COUNT=1000000`, `DURATION=30s`로 실행했다.

| VU | Baseline Avg | 인덱스 Avg | Baseline p95 | 인덱스 p95 | Baseline 처리량 | 인덱스 처리량 | 오류율 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 649.71ms | 3.65ms | 706.32ms | 4.72ms | 1.54 req/s | 267.98 req/s | 0% |
| 10 | 885.42ms | 5.96ms | 990.55ms | 7.69ms | 11.20 req/s | 1,648.05 req/s | 0% |
| 50 | 4.44s | 17.71ms | 5.06s | 26.03ms | 11.04 req/s | 2,793.31 req/s | 0% |

| VU | Avg 개선 | p95 개선 | 처리량 배수 | 총 요청 수 | 최대 지연시간 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 99.44% 감소 | 99.33% 감소 | 174.01x | 8,040 | 18.04ms |
| 10 | 99.33% 감소 | 99.22% 감소 | 147.15x | 49,449 | 61.13ms |
| 50 | 99.60% 감소 | 99.49% 감소 | 253.02x | 83,830 | 97.27ms |

## EXPLAIN ANALYZE 비교

대표 회원 ID `500000`으로 동일 조회 SQL을 실행했다.

```sql
EXPLAIN ANALYZE
SELECT coupon_issue_id, coupon_id, member_id, status, issued_at
FROM coupon_issue
WHERE member_id = 500000
ORDER BY issued_at DESC;
```

| 조건 | 실행계획 | 실제 rows | 실행시간 |
| --- | --- | ---: | ---: |
| Baseline | Full table scan 후 정렬, 인덱스 없음 | 3,000,000 → 결과 3건 | 698ms |
| 인덱스 적용 | `idx_coupon_issue_member_issued_at` index lookup | 3건 | 0.0283..0.0294ms |

인덱스 적용 후 MySQL은 `member_id=500000`에 대해 비용 `3.3`, 추정 rows `3`의 인덱스 조회를
수행했고 추가 정렬 노드는 나타나지 않았다.

## 관찰

- 조회 병목이었던 Full Scan과 정렬이 제거되어 모든 VU에서 p95가 밀리초 단위로 낮아졌다.
- 50 VU에서도 p95가 `5.06s`에서 `26.03ms`로 낮아져, 이 조건의 회원별 조회 병목은 해소됐다.
- k6 2.2.0은 무작위 회원 ID가 포함된 URL마다 고유 시계열을 만들어 10·50 VU 측정 중 high-cardinality 경고를 출력했다. 이 경고는 Baseline과 동일 스크립트를 유지한 결과이며, 인덱스 가설 검증을 위해 스크립트는 변경하지 않았다.
- 이 결과는 동일 로컬 머신 조건에서의 전후 비교이며, 절대 처리량으로 해석하지 않는다.
