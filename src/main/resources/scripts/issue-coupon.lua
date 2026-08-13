-- KEYS[1]에 저장된 쿠폰 재고 수량 조회
-- 예: coupon:stock:1
local stock = redis.call('GET', KEYS[1])


-- 재고 Key 자체가 존재하지 않는 경우
-- -2: 존재하지 않는 쿠폰 또는 재고 정보 없음
if not stock then
	return -2
end


-- KEYS[2]의 Set에 현재 사용자(ARGV[1])가 이미 존재하는지 확인
-- SISMEMBER는 존재하면 1, 존재하지 않으면 0 반환
-- 이미 발급받은 사용자라면 중복 발급 방지
-- -1: 이미 쿠폰을 발급받은 사용자
if redis.call('SISMEMBER', KEYS[2], ARGV[1]) == 1 then
	return -1
end


-- GET으로 가져온 stock은 문자열이므로 tonumber()로 숫자로 변환
-- 재고가 0 이하이면 더 이상 발급할 수 없음
-- 0: 쿠폰 재고 소진
if tonumber(stock) <= 0 then
	return 0
end


-- 쿠폰 재고를 1 감소
redis.call('DECR', KEYS[1])

-- 쿠폰을 발급받은 사용자 ID를 Set에 추가
-- 이후 같은 사용자가 요청하면 위 SISMEMBER에서 중복 발급 차단
redis.call('SADD', KEYS[2], ARGV[1])


-- 모든 처리가 정상적으로 완료됨
-- 1: 쿠폰 발급 성공
return 1