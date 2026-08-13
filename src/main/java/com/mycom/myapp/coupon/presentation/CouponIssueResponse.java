package com.mycom.myapp.coupon.presentation;

import com.mycom.myapp.coupon.domain.CouponIssue;
import java.time.LocalDateTime;

public record CouponIssueResponse(
	Long couponIssueId,
	Long couponId,
	Long memberId,
	LocalDateTime issuedAt
) {
	public static CouponIssueResponse from(CouponIssue couponIssue) {
		return new CouponIssueResponse(
			couponIssue.getCouponIssueId(),
			couponIssue.getCoupon().getId(),
			couponIssue.getMember().getMemberId(),
			couponIssue.getIssuedAt()
		);
	}
}
