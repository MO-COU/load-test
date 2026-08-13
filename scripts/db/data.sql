SET SESSION cte_max_recursion_depth = 2000;

INSERT IGNORE INTO members (member_id)
WITH RECURSIVE sequence AS (
    SELECT 1 AS member_id
    UNION ALL
    SELECT member_id + 1 FROM sequence WHERE member_id < 2000
)
SELECT member_id FROM sequence;

INSERT INTO coupons (coupon_id, name, quantity)
VALUES (1, '선착순 쿠폰', 1000)
ON DUPLICATE KEY UPDATE
    name = '선착순 쿠폰',
    quantity = 1000;
