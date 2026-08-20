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

	/** 동기 issue()의 비동기 버전. 큐에 넣고 바로 202를 반환한다(DB 반영은 나중에 배치로). */
	@PostMapping("/benchmark/coupon-issues/async")
	public ResponseEntity<Void> issueAsync(@RequestParam long couponId, @RequestParam long memberId) {
		service.issueAsync(couponId, memberId);
		return ResponseEntity.accepted().build();
	}

	@PatchMapping("/benchmark/coupon-issues/status/async")
	public ResponseEntity<Void> markUsedAsync(@RequestParam long couponId, @RequestParam long memberId) {
		service.markUsedAsync(couponId, memberId);
		return ResponseEntity.accepted().build();
	}

	/** 큐 적체(lag) 관측용. 부하 도중 이 값을 폴링하면 컨슈머가 못 따라가는 시점을 볼 수 있다. */
	@GetMapping("/benchmark/coupon-issues/queue-size")
	public int asyncQueueSize() {
		return service.asyncQueueSize();
	}
}
