package com.example.demo.coupon.application;

import com.example.demo.common.exception.CouponNotFoundException;
import com.example.demo.common.exception.DuplicateIssueException;
import com.example.demo.common.exception.SoldOutException;
import com.example.demo.coupon.domain.Coupon;
import com.example.demo.coupon.domain.CouponIssue;
import com.example.demo.coupon.domain.CouponIssueRepository;
import com.example.demo.coupon.domain.CouponRepository;
import java.time.LocalDateTime;
import org.redisson.api.RLock;
import org.redisson.api.RedissonClient;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * Redisson RLock 방식.
 *
 * 쿠폰별 분산 락으로 한 번에 한 요청만 발급 로직에 진입시킨다.
 * Redis는 락에만 사용하고, 실제 재고와 발급 이력은 DB 트랜잭션으로 처리한다.
 */
@Service
public class CouponIssueService {

	private final CouponRepository couponRepository;
	private final CouponIssueRepository couponIssueRepository;
	private final RedissonClient redissonClient;
	private final TransactionTemplate transactionTemplate;

	public CouponIssueService(
		CouponRepository couponRepository,
		CouponIssueRepository couponIssueRepository,
		RedissonClient redissonClient,
		TransactionTemplate transactionTemplate
	) {
		this.couponRepository = couponRepository;
		this.couponIssueRepository = couponIssueRepository;
		this.redissonClient = redissonClient;
		this.transactionTemplate = transactionTemplate;
	}

	public void issue(Long couponId, Long memberId) {
		RLock lock = redissonClient.getLock("coupon:" + couponId + ":issue:lock");

		lock.lock();

		try {
			transactionTemplate.executeWithoutResult(
				status -> issueInTransaction(couponId, memberId)
			);
		} finally {
			if (lock.isHeldByCurrentThread()) {
				lock.unlock();
			}
		}
	}

	private void issueInTransaction(Long couponId, Long memberId) {
		Coupon coupon = couponRepository.findById(couponId)
			.orElseThrow(() -> new CouponNotFoundException(couponId));

		if (coupon.isSoldOut()) {
			throw new SoldOutException(couponId);
		}

		// Dirty Checking 으로 트랜잭션 종료 시 UPDATE 된다.
		coupon.increaseIssuedCount();

		try {
			couponIssueRepository.saveAndFlush(
				new CouponIssue(couponId, memberId, LocalDateTime.now())
			);
		} catch (DataIntegrityViolationException e) {
			throw new DuplicateIssueException(couponId, memberId);
		}
	}
}
