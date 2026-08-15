-- 부하테스트 직후 정확성 판정.
--
--   docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"
--
-- Redis 재고는 SQL 로 볼 수 없어 기대값만 찍는다. 아래와 대조한다.
-- 다르면 보상 로직이 재고를 되돌리지 않은 것이다.
--
--   docker compose exec -T redis redis-cli GET coupon:stock:1

-- 컬럼명을 영문으로 두는 이유: 터미널은 한글을 두 칸으로 그리는데
-- MySQL 은 한 글자로 세어 표 정렬이 어긋난다.
SELECT
	c.total_quantity                          AS stock,
	c.issued_count                            AS counter,
	r.issued_rows                             AS issued_rows,
	d.dup_members                             AS dup_members,
	-- 카운터가 아닌 행 수로 판정한다. 재고를 Redis 가 관리하는 브랜치는
	-- coupon.issued_count 를 쓰지 않아 카운터로는 판정할 수 없다.
	IF(r.issued_rows > c.total_quantity, 'FAIL', 'PASS')  AS oversell,
	-- 카운터를 안 쓰면 0 으로 남으므로 N/A. 값이 있는데 행 수와 다르면 버그.
	IF(c.issued_count = 0, 'N/A',
	   IF(c.issued_count = r.issued_rows, 'PASS', 'FAIL'))  AS counter_ok,
	IF(d.dup_members > 0,                    'FAIL', 'PASS')  AS duplicate,
	-- redis-lua, redis-watch 만 의미가 있다. 실제 Redis 재고가 이 값과 같아야 한다.
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
