package com.example.demo.coupon.infrastructure;

import java.util.List;

import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.stereotype.Component;

import lombok.RequiredArgsConstructor;

/**
 * Redis를 이용한 쿠폰 발급 예약과 보상을 담다.
 *
 * Spring Data Redis는 기본 Lettuce 연결을 사용.
 * Lua 스크립트는 Redis 내부에서 원자적으로 실행.
 */
@Component
@RequiredArgsConstructor
public class RedisCouponIssueGateway {

    /*
     * issue-coupon.lua 반환값
     *
     *  1: 발급 예약 성공
     *  0: 재고 소진
     * -1: 중복 발급
     * -2: 재고 키가 초기화되지 않음
     */
    private static final long ISSUE_SUCCESS = 1L;
    private static final long SOLD_OUT = 0L;
    private static final long DUPLICATED = -1L;
    private static final long STOCK_NOT_INITIALIZED = -2L;

    /*
     * compensate-coupon.lua 반환값
     *
     * 1: 회원 제거와 재고 복구 완료
     * 0: 이미 복구됐거나 복구할 예약이 없음
     */
    private static final long COMPENSATION_APPLIED = 1L;
    private static final long COMPENSATION_NOT_NEEDED = 0L;

    private static final String STOCK_KEY_PREFIX = "coupon:stock:";

    private static final String ISSUED_MEMBERS_KEY_PREFIX =
        "coupon:issued-members:";

    /*
     * RedisScript는 스크립트의 SHA1을 계산.
     * Spring Data Redis는 EVALSHA를 먼저 실행,
     * Redis에 스크립트가 없으면 EVAL로 다시 실행.
     */
    private static final RedisScript<Long> ISSUE_SCRIPT =
        RedisScript.of(
            new ClassPathResource("scripts/issue-coupon.lua"),
            Long.class
        );

    private static final RedisScript<Long> COMPENSATE_SCRIPT =
        RedisScript.of(
            new ClassPathResource("scripts/compensate-coupon.lua"),
            Long.class
        );

    private final StringRedisTemplate redisTemplate;

    /**
     * 중복 확인과 재고 차감을 하나의 Lua 스크립트로 실행.
     */
    public ReservationResult reserve(Long couponId, Long memberId) {
        Long result = redisTemplate.execute(
            ISSUE_SCRIPT,
            createCouponKeys(couponId),
            memberId.toString()
        );

        if (result == null) {
            throw new IllegalStateException(
                "Redis issue script returned null"
            );
        }

        return toReservationResult(result);
    }

    /**
     * MySQL 저장 실패 시 Redis에서 처리한 발급 예약을 되돌림.
     *
     * Lua 내부에서 SREM이 실제로 회원을 제거한 경우에만 INCR을
     * 실행하므로 동일한 보상이 반복돼도 재고가 여러 번 증가하지 않음.
     */
    public CompensationResult compensate(
        Long couponId,
        Long memberId
    ) {
        Long result = redisTemplate.execute(
            COMPENSATE_SCRIPT,
            createCouponKeys(couponId),
            memberId.toString()
        );

        if (result == null) {
            throw new IllegalStateException(
                "Redis compensation script returned null"
            );
        }

        if (result == COMPENSATION_APPLIED) {
            return CompensationResult.APPLIED;
        }

        if (result == COMPENSATION_NOT_NEEDED) {
            return CompensationResult.NOT_NEEDED;
        }

        if (result == STOCK_NOT_INITIALIZED) {
            throw new IllegalStateException(
                "Redis stock is missing during compensation: coupon="
                    + couponId
            );
        }

        throw new IllegalStateException(
            "Unexpected Redis compensation result: " + result
        );
    }

    private ReservationResult toReservationResult(long result) {
        if (result == ISSUE_SUCCESS) {
            return ReservationResult.SUCCESS;
        }

        if (result == SOLD_OUT) {
            return ReservationResult.SOLD_OUT;
        }

        if (result == DUPLICATED) {
            return ReservationResult.DUPLICATED;
        }

        if (result == STOCK_NOT_INITIALIZED) {
            return ReservationResult.STOCK_NOT_INITIALIZED;
        }

        throw new IllegalStateException(
            "Unexpected Redis issue result: " + result
        );
    }

    /**
     * KEYS[1]: 쿠폰 재고
     * KEYS[2]: 발급받은 회원 Set
     */
    private List<String> createCouponKeys(Long couponId) {
        return List.of(
            STOCK_KEY_PREFIX + couponId,
            ISSUED_MEMBERS_KEY_PREFIX + couponId
        );
    }

    public enum ReservationResult {
        SUCCESS,
        SOLD_OUT,
        DUPLICATED,
        STOCK_NOT_INITIALIZED
    }

    public enum CompensationResult {
        APPLIED,
        NOT_NEEDED
    }
}