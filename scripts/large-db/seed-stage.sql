-- 대용량 실험 단계 데이터 적재.
-- 실행 전 @member_count를 설정한다. 설정하지 않으면 Stage 1(회원 10만)을 사용한다.
-- 예: SET @member_count = 100000; source /scripts/large-db/seed-stage.sql

SET @member_count = IFNULL(@member_count, 100000);

TRUNCATE TABLE coupon_issue;
TRUNCATE TABLE member;
TRUNCATE TABLE coupon;

-- 회원별 이력 3건을 만들기 위해 서로 다른 쿠폰 3개를 사용한다.
INSERT INTO coupon (coupon_id, name, total_quantity, issued_count, version)
VALUES
    (1, '대용량 실험 쿠폰 A', @member_count, 0, 0),
    (2, '대용량 실험 쿠폰 B', @member_count, 0, 0),
    (3, '대용량 실험 쿠폰 C', @member_count, 0, 0);

-- 0부터 999,999까지의 숫자를 만들고 필요한 회원 수만 적재한다.
INSERT INTO member (member_id, created_at)
SELECT numbers.member_id, NOW(6)
FROM (
    SELECT d0.n + d1.n * 10 + d2.n * 100 + d3.n * 1000 + d4.n * 10000 + d5.n * 100000 + 1 AS member_id
    FROM (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d0
    CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d1
    CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d2
    CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d3
    CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d4
    CROSS JOIN (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d5
) AS numbers
WHERE numbers.member_id <= @member_count
ORDER BY numbers.member_id;

-- 쿠폰 3개 × 회원 수로 발급 이력을 만든다. 상태는 50:50으로 고정한다.
INSERT INTO coupon_issue (coupon_id, member_id, status, issued_at)
SELECT
    coupon.coupon_id,
    member.member_id,
    CASE WHEN MOD(coupon.coupon_id + member.member_id, 2) = 0 THEN 'USED' ELSE 'ISSUED' END,
    NOW(6)
FROM member
CROSS JOIN coupon;
