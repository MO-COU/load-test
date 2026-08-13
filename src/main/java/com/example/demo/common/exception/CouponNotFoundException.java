package com.example.demo.common.exception;

/**
 * HTTP 404. k6는 항상 couponId=1을 보내므로 실험 중에는 발생하지 않아야 한다.
 * 발생한다면 초기화 누락 신호이며, k6의 errors 카운터에 잡힌다.
 */
public class CouponNotFoundException extends RuntimeException {

	public CouponNotFoundException(Long couponId) {
		super("coupon not found: " + couponId);
	}
}
