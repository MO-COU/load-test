package com.example.demo.benchmark;

import java.util.List;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class BenchmarkCouponIssueService {

	private final BenchmarkCouponIssueRepository repository;
	private final AsyncIssueQueue queue;

	public BenchmarkCouponIssueService(BenchmarkCouponIssueRepository repository, AsyncIssueQueue queue) {
		this.repository = repository;
		this.queue = queue;
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

	/** 큐에 넣기만 하고 즉시 반환한다. 실제 DB 반영은 {@link AsyncCouponIssueConsumer}가 나중에 배치로 한다. */
	public void issueAsync(long couponId, long memberId) {
		queue.enqueue(new AsyncIssueEvent(AsyncIssueEvent.EventType.INSERT, couponId, memberId));
	}

	public void markUsedAsync(long couponId, long memberId) {
		queue.enqueue(new AsyncIssueEvent(AsyncIssueEvent.EventType.MARK_USED, couponId, memberId));
	}

	/** 큐 적체(lag) 관측용 — 부하 도중 폴링해서 컨슈머가 못 따라가는지 본다. */
	public int asyncQueueSize() {
		return queue.size();
	}

	/**
	 * {@link AsyncCouponIssueConsumer}가 모은 배치를 한 트랜잭션(=한 커밋)으로 반영한다.
	 * INSERT와 MARK_USED가 섞여 있어도 이 메서드 호출 하나가 커밋 하나다 —
	 * fsync 1번으로 여러 건을 처리하는 배치 효과가 여기서 생긴다.
	 */
	@Transactional
	public void flushBatch(List<AsyncIssueEvent> inserts, List<AsyncIssueEvent> markUsed) {
		if (!inserts.isEmpty()) {
			repository.insertBatch(inserts);
		}
		if (!markUsed.isEmpty()) {
			repository.markUsedBatch(markUsed);
		}
	}
}
