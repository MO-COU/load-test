package com.example.demo.common.exception;

/** 재고 소진. HTTP 409 + 본문 SOLD_OUT */
public class SoldOutException extends RuntimeException {

	public SoldOutException(Long couponId) {
		super("coupon sold out: " + couponId);
	}
}
