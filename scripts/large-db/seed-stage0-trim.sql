-- Stage 0(이 실험 전용) 시드: coupon_issue를 정확히 10,000건으로 맞춘다.
--
-- seed-stage.sql은 coupon_issue = member_count * 3(코폰 3개)이라 정수로
-- 딱 10,000을 만드는 member_count가 없다(3,334 -> 10,002). 그래서 기존
-- seed-stage.sql은 그대로 두고, 여기서 3,334로 시드한 뒤 초과분 2건만
-- 지워 정확히 10,000건으로 맞춘다.
--
-- 실행:
--   docker compose -f docker-compose.large-db.yml exec -T mysql-large \
--     mysql -ucoupon_large -pcoupon-large-1234 coupon_large \
--     -e "source /scripts/large-db/seed-stage0-trim.sql"

SET @member_count = 3334;

source /scripts/large-db/seed-stage.sql

DELETE FROM coupon_issue
ORDER BY coupon_issue_id DESC
LIMIT 2;
