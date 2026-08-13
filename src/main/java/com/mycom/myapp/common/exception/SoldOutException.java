package com.mycom.myapp.common.exception;

public class SoldOutException extends RuntimeException {

	public SoldOutException(Long couponId) {
		super("쿠폰 재고가 없습니다. couponId=" + couponId);
	}
}
