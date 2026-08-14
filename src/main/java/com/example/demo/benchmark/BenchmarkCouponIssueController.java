package com.example.demo.benchmark;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class BenchmarkCouponIssueController {

	private final BenchmarkCouponIssueService service;

	public BenchmarkCouponIssueController(BenchmarkCouponIssueService service) {
		this.service = service;
	}

	@GetMapping("/benchmark/members/{memberId}/coupon-issues")
	public List<CouponIssueRow> findByMemberId(@org.springframework.web.bind.annotation.PathVariable long memberId) {
		return service.findByMemberId(memberId);
	}

	@PostMapping("/benchmark/coupon-issues")
	public ResponseEntity<Void> issue(@RequestParam long couponId, @RequestParam long memberId) {
		service.issue(couponId, memberId);
		return ResponseEntity.status(HttpStatus.CREATED).build();
	}

	@PatchMapping("/benchmark/coupon-issues/status")
	public ResponseEntity<Void> markUsed(@RequestParam long couponId, @RequestParam long memberId) {
		return service.markUsed(couponId, memberId)
			? ResponseEntity.noContent().build()
			: ResponseEntity.notFound().build();
	}

	@GetMapping("/benchmark/coupon-issues/summary")
	public List<CouponIssueSummary> summarize() {
		return service.summarize();
	}
}
