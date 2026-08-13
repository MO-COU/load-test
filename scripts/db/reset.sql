-- 매 부하테스트 직전에 실행한다. 빠뜨리면 이전 실행 결과가 섞인다.
--
--   docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon < scripts/db/reset.sql
--   docker compose exec redis redis-cli FLUSHALL
--   # Redis 방식 브랜치만 추가
--   docker compose exec redis redis-cli SET coupon:stock:1 1000
--
-- ERROR 1045 Access denied 가 나면 MySQL 초기화가 아직 안 끝난 것이다.
-- docker compose ps 로 mysql 이 healthy 인지 먼저 확인한다.

-- DELETE 대신 TRUNCATE: 즉시 완료되고 AUTO_INCREMENT까지 리셋되어
-- 매 실행이 완전히 동일한 상태에서 시작한다. FK가 없으므로 사용 가능하다.
TRUNCATE TABLE coupon_issue;

-- total_quantity는 건드리지 않는다. 재고를 바꿔 추가 실험을 하더라도
-- 이 파일은 수정할 필요가 없다.
UPDATE coupon SET issued_count = 0, version = 0;
