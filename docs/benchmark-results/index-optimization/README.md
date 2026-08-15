# 조회 인덱스 최적화 공통 해석

적용 인덱스: `idx_coupon_issue_member_issued_at (member_id, issued_at DESC)`

## 쓰기 부하 해석

INSERT와 UPDATE는 최대 50 VU에서 VU당 1,000회, 총 50,000건을 실행했다. 이번 시나리오에서는
요청마다 서로 다른 회원 행을 사용하므로 동일 행의 잠금 경합이 거의 없다.

- INSERT는 쿠폰 4와 고유 회원 ID 조합을 사용한다. 새 복합 인덱스 엔트리를 추가하는 비용은 있지만,
  중복 키·부모 FK·재고 행 경합이 없어 비용이 작게 나타난다.
- UPDATE는 `(coupon_id, member_id)` 유니크 인덱스로 대상 한 건을 찾고 `status`만 변경한다.
  새 인덱스의 키인 `member_id`, `issued_at`은 변경하지 않으므로 해당 인덱스를 재구성하지 않는다.
- 실제 발급 흐름의 재고 차감, 같은 재고 행 잠금, 멱등성 확인, 다중 테이블 트랜잭션은 포함하지 않았다.
  따라서 이 결과는 “현재 단일 테이블·비경합 쓰기 조건에서의 인덱스 유지 비용”으로만 해석한다.

## 집계 결과 해석

집계 쿼리는 `coupon_id, status`로 전체 이력을 그룹화한다. 적용 인덱스의 선두 컬럼은 `member_id`이고
집계 쿼리에 `member_id` 조건이 없으므로 MySQL은 이 인덱스를 사용하지 않는다.

모든 측정 Stage의 `EXPLAIN ANALYZE`는 다음 경로를 확인했다.

```text
Table scan on coupon_issue
→ Aggregate using temporary table
→ Sort: coupon_id, status
```

따라서 Stage 3·4의 k6 집계 지연·처리량 차이는 조회 인덱스의 효과로 해석하지 않는다. 재시드 후
다시 실행해 확정한 Stage 3·4 p95는 Baseline에 근접하거나 이를 초과했다. 실행계획 비교도 Stage 3은 Baseline `758ms`와 인덱스 적용 `814ms`,
Stage 4는 Baseline `1.694s`와 인덱스 적용 `1.678s`로, 집계 쿼리 자체의 유의미한 개선을 뒷받침하지 않는다.

집계 성능 차이의 원인을 수치로 검증하려면 인덱스 적용 상태만 다시 측정하는 것으로는 부족하다.
동일 데이터·동일 머신·동일 부하 조건에서 조회 인덱스를 `INVISIBLE`로 전환한 상태와 `VISIBLE` 상태를
반복 비교하는 별도 통제 실험이 필요하다. 집계 최적화는 `(coupon_id, status)` 인덱스를 별도 가설로
검증한다.
