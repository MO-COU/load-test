package com.mycom.myapp.common.exception;

public class CouponNotFoundException extends RuntimeException {

	public CouponNotFoundException(Long couponId) {
		super("쿠폰을 찾을 수 없습니다. couponId=" + couponId);
	}
}
