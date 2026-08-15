-- 부하테스트 직후 정확성 판정.
--
--   docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"
--
-- 숫자를 눈으로 비교하지 않도록 PASS/FAIL 로 찍는다.
-- 브랜치 6개 x 3회 = 18번 판정하므로 사람이 대조하면 반드시 놓친다.
--
-- Redis 재고만 SQL 로 볼 수 없다. 기대값을 같이 찍어주므로 아래를 실행해
-- 숫자 하나만 대조하면 된다. 다르면 보상 로직이 재고를 되돌리지 않은 것이다.
--
--   docker compose exec -T redis redis-cli GET coupon:stock:1

SELECT
	c.total_quantity                          AS `재고`,
	c.issued_count                            AS `카운터`,
	r.issued_rows                             AS `실제행수`,
	d.dup_members                             AS `중복회원`,
	-- 실제 발급 행 수가 재고를 넘으면 초과 발급.
	-- 카운터가 아니라 행 수로 판정한다. 재고를 Redis 가 관리하는 브랜치는
	-- coupon.issued_count 를 아예 쓰지 않아 카운터로는 판정할 수 없다.
	IF(r.issued_rows > c.total_quantity, 'FAIL', 'PASS')  AS `초과발급`,
	-- 카운터를 쓰는 브랜치에서만 의미가 있다. 안 쓰면 0 으로 남으므로 N/A.
	-- 값이 있는데 행 수와 다르면 롤백/보상이 어긋난 것이다.
	IF(c.issued_count = 0, 'N/A',
	   IF(c.issued_count = r.issued_rows, 'PASS', 'FAIL'))  AS `카운터일치`,
	-- 한 회원이 2행 이상이면 1인 1매가 깨진 것.
	IF(d.dup_members > 0,                    'FAIL', 'PASS')  AS `중복발급`,
	-- Redis 방식 브랜치는 실제 Redis 재고가 이 값과 같아야 한다.
	c.total_quantity - r.issued_rows          AS `Redis재고_기대값`
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

-- FAIL 이 났을 때만 행이 나온다. 어느 회원이 중복됐는지 확인용.
SELECT member_id, COUNT(*) AS cnt
FROM coupon_issue
WHERE coupon_id = 1
GROUP BY member_id
HAVING COUNT(*) > 1
LIMIT 10;
