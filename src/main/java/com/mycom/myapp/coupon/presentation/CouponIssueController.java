package com.mycom.myapp.coupon.presentation;

import com.mycom.myapp.coupon.application.CouponIssueService;
import com.mycom.myapp.coupon.domain.CouponIssue;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/coupons")
public class CouponIssueController {

	private final CouponIssueService couponIssueService;

	public CouponIssueController(CouponIssueService couponIssueService) {
		this.couponIssueService = couponIssueService;
	}

	@PostMapping("/{couponId}/issue")
	public ResponseEntity<CouponIssueResponse> issue(
		@PathVariable Long couponId,
		@RequestBody CouponIssueRequest request
	) {
		CouponIssue couponIssue = couponIssueService.issue(couponId, request.memberId());
		return ResponseEntity.status(HttpStatus.CREATED).body(CouponIssueResponse.from(couponIssue));
	}
}
