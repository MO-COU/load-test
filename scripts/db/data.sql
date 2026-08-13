-- 시드 데이터. 최초 1회만 실행된다(docker-entrypoint-initdb.d).
-- member 테이블이 없으므로 회원 시드는 필요 없다. member_id는 k6가 만들어 보낸다.

-- 재고를 바꾸려면 total_quantity 값만 고친다.
-- reset.sql은 total_quantity를 건드리지 않으므로 초기화 SQL은 그대로 둔다.
INSERT INTO coupon (coupon_id, name, total_quantity, issued_count, version)
VALUES (1, '선착순 쿠폰', 1000, 0, 0)
ON DUPLICATE KEY UPDATE
    name           = '선착순 쿠폰',
    total_quantity = 1000,
    issued_count   = 0,
    version        = 0;
