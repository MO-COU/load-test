package com.example.demo.common.exception;

/**
 * 낙관적 재시도(WATCH/버전 충돌)가 MAX_RETRY 안에 안 풀림.
 * 숨기지 않고 5xx 로 드러낸다 — 고경합에서 낙관적 방식의 한계를 보여주는 측정값 그 자체.
 * Controller 가 따로 잡지 않으므로 스프링 기본 처리로 500 이 나간다.
 */
public class OptimisticRetryExhaustedException extends RuntimeException {

	public OptimisticRetryExhaustedException(Long couponId, Long memberId) {
		super("optimistic retry exhausted: coupon=" + couponId + ", member=" + memberId);
	}
}
