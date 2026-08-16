-- EC2 측정 직후 결과 확인.
--
--   docker compose exec -T mysql mysql -t -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"
--
-- redis_expect 는 Redis 재고의 기대값이다. 아래와 대조한다.
--
--   docker compose exec -T redis redis-cli GET coupon:stock:1

SELECT
	c.total_quantity                          AS stock,
	c.issued_count                            AS counter,
	r.issued_rows                             AS issued_rows,
	d.dup_members                             AS dup_members,
	IF(r.issued_rows > c.total_quantity, 'FAIL', 'PASS')  AS oversell,
	-- Redis 방식은 카운터를 안 써 0 으로 남으므로 N/A.
	IF(c.issued_count = 0, 'N/A',
	   IF(c.issued_count = r.issued_rows, 'PASS', 'FAIL'))  AS counter_ok,
	IF(d.dup_members > 0,                    'FAIL', 'PASS')  AS duplicate,
	-- redis-lua, redis-watch 만 해당.
	c.total_quantity - r.issued_rows          AS redis_expect
FROM coupon c
CROSS JOIN (
	SELECT COUNT(*) AS issued_rows
	FROM coupon_issue WHERE coupon_id = 1
) r
CROSS JOIN (
	SELECT COUNT(*) AS dup_members FROM (
		SELECT member_id
		FROM coupon_issue
		WHERE coupon_id = 1
		GROUP BY member_id
		HAVING COUNT(*) > 1
	) x
) d
WHERE c.coupon_id = 1;

-- FAIL 일 때만 행이 나온다. 어느 회원이 중복됐는지 확인용.
SELECT member_id, COUNT(*) AS cnt
FROM coupon_issue
WHERE coupon_id = 1
GROUP BY member_id
HAVING COUNT(*) > 1
LIMIT 10;
