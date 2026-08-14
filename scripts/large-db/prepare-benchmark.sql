-- 대용량 벤치마크 측정 전 상태 복구 스크립트.
-- INSERT/UPDATE 부하를 "반복 실행"할 때, 매 실행 직전에 이 스크립트로 측정 대상을 시드 기준 상태로 되돌린다.
-- (READ/SUMMARY는 상태를 바꾸지 않으므로 필수는 아니지만, 실행해도 무해하다.)
--
-- 실행:
--   docker compose -f docker-compose.large-db.yml exec -T mysql-large \
--     mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/prepare-benchmark.sql"

-- INSERT 측정용 쿠폰 4를 준비한다(없으면 생성). 시드(seed-stage.sql)는 쿠폰 1~3만 만든다.
INSERT INTO coupon (coupon_id, name, total_quantity, issued_count, version)
VALUES (4, '대용량 실험 쿠폰 D(INSERT 측정용)', 100000000, 0, 0)
ON DUPLICATE KEY UPDATE name = VALUES(name);

-- INSERT 측정 대상 초기화: 쿠폰 4의 발급 이력을 모두 제거해 매 실행이 빈 상태에서 시작하게 한다.
DELETE FROM coupon_issue WHERE coupon_id = 4;

-- UPDATE 측정 대상 복구: 쿠폰 1~3의 상태를 시드와 동일한 50:50(ISSUED/USED)으로 되돌린다.
-- (UPDATE 부하가 ISSUED -> USED 로 바꾼 것을 원복해, 다음 실행도 같은 조건에서 시작한다.)
UPDATE coupon_issue
SET status = CASE WHEN MOD(coupon_id + member_id, 2) = 0 THEN 'USED' ELSE 'ISSUED' END
WHERE coupon_id IN (1, 2, 3);