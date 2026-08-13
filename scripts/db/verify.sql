-- 부하테스트 직후 결과 확인.
--
--   docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"

-- 카운터. issued_count 가 total_quantity 를 넘었다면 초과 발급이다.
SELECT total_quantity, issued_count FROM coupon WHERE coupon_id = 1;

-- 실제 발급 행 수. 위 issued_count 와 다르면 그 자체가 발견이다.
SELECT COUNT(*) AS issued_rows FROM coupon_issue WHERE coupon_id = 1;

-- 중복 발급. 한 행이라도 나오면 1인 1매 한도가 깨진 것이다.
SELECT member_id, COUNT(*) AS cnt
FROM coupon_issue
WHERE coupon_id = 1
GROUP BY member_id
HAVING COUNT(*) > 1;
