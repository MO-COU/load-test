-- Stage 4 조회 인덱스 가설 적용 스크립트.
-- 대상: SELECT ... FROM coupon_issue WHERE member_id = ? ORDER BY issued_at DESC
--
-- 실행:
--   docker compose -f docker-compose.large-db.yml exec -T mysql-large \
--     mysql -ucoupon_large -pcoupon-large-1234 coupon_large \
--     -e "source /scripts/large-db/apply-read-index.sql"

ALTER TABLE coupon_issue
    ADD INDEX idx_coupon_issue_member_issued_at (member_id, issued_at DESC);
