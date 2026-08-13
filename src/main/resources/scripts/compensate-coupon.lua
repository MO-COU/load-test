-- KEYS[1]에 해당하는 쿠폰 재고 Key가 존재하는지 확인
-- EXISTS는 Key가 존재하면 1, 존재하지 않으면 0 반환
-- -2: 존재하지 않는 쿠폰 또는 재고 정보 없음
if redis.call('EXISTS', KEYS[1]) == 0 then
    return -2
end


-- KEYS[2]의 발급 사용자 Set에서 현재 사용자(ARGV[1])를 제거
-- SREM은 실제로 값이 제거되면 1, 해당 값이 없으면 0 반환
--
-- 즉, 사용자가 실제로 쿠폰을 발급받은 상태라면
-- 발급 기록에서 사용자 ID를 제거
if redis.call('SREM', KEYS[2], ARGV[1]) == 1 then

    -- 쿠폰 발급을 취소했으므로
    -- 기존에 감소했던 쿠폰 재고를 다시 1 증가
    redis.call('INCR', KEYS[1])

    -- 1: 쿠폰 발급 취소 성공
    return 1
end


-- SREM 결과가 0이라는 것은
-- 해당 사용자가 쿠폰을 발급받은 기록이 없다는 의미
-- 0: 취소할 쿠폰 발급 기록 없음
return 0