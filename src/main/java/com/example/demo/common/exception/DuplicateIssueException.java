package com.example.demo.common.exception;

/** 1인 1매 한도 위반. HTTP 409 + 본문 DUPLICATED */
public class DuplicateIssueException extends RuntimeException {

	public DuplicateIssueException(Long couponId, Long memberId) {
		super("already issued: coupon=" + couponId + ", member=" + memberId);
	}
}
