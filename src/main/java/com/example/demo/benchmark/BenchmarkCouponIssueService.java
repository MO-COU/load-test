package com.example.demo.benchmark;

import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class BenchmarkCouponIssueService {

	private final BenchmarkCouponIssueRepository repository;

	public BenchmarkCouponIssueService(BenchmarkCouponIssueRepository repository) {
		this.repository = repository;
	}

	@Transactional(readOnly = true)
	public List<CouponIssueRow> findByMemberId(long memberId) {
		return repository.findByMemberId(memberId);
	}

	@Transactional
	public void issue(long couponId, long memberId) {
		repository.insert(couponId, memberId);
	}

	@Transactional
	public boolean markUsed(long couponId, long memberId) {
		return repository.markUsed(couponId, memberId) == 1;
	}

	@Transactional(readOnly = true)
	public List<CouponIssueSummary> summarize() {
		return repository.summarize();
	}
}
