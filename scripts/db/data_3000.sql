-- 3,000장 쿠폰 부하테스트용 초기화.
-- 기존 Docker 볼륨에도 source로 바로 적용할 수 있다.

TRUNCATE TABLE coupon_issue;

INSERT INTO coupon (coupon_id, name, total_quantity, issued_count, version)
VALUES (1, '선착순 쿠폰', 3000, 0, 0)
ON DUPLICATE KEY UPDATE
    name           = '선착순 쿠폰',
    total_quantity = 3000,
    issued_count   = 0,
    version        = 0;
