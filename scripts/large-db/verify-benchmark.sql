-- 대용량 벤치마크 데이터 상태 확인 스크립트.
-- 회원 수, 전체 발급 이력 수, 쿠폰 4 발급 이력 수, 쿠폰·상태별 건수를 확인한다.
--
-- 실행:
--   docker compose -f docker-compose.large-db.yml exec -T mysql-large \
--     mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/verify-benchmark.sql"
--
-- Stage 1 기대값: member 100,000 / coupon_issue 300,000 (쿠폰 1~3 각 100,000) /
--   쿠폰 4는 INSERT 측정 결과에 따라 변동 / 쿠폰 1~3은 각 ISSUED 50,000·USED 50,000.

SELECT COUNT(*) AS member_count FROM member;

SELECT COUNT(*) AS coupon_issue_count FROM coupon_issue;

SELECT COUNT(*) AS coupon4_issue_count FROM coupon_issue WHERE coupon_id = 4;

SELECT coupon_id, status, COUNT(*) AS issue_count
FROM coupon_issue
GROUP BY coupon_id, status
ORDER BY coupon_id, status;