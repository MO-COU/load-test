package com.example.demo.coupon.application;

import com.example.demo.common.exception.CouponNotFoundException;
import com.example.demo.common.exception.DuplicateIssueException;
import com.example.demo.common.exception.SoldOutException;
import com.example.demo.coupon.domain.Coupon;
import com.example.demo.coupon.domain.CouponIssue;
import com.example.demo.coupon.domain.CouponIssueRepository;
import com.example.demo.coupon.domain.CouponRepository;
import java.time.LocalDateTime;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Baseline: 동시성 제어를 하지 않는다.
 *
 * 락, 조건부 UPDATE, Redis, synchronized 를 일절 쓰지 않으므로
 * 재고 확인과 증가 사이에 경합이 발생하면 초과 발급이 난다.
 * 그것이 이 구현의 목적이며, 나머지 6개 방식의 비교 기준이 된다.
 *
 * 각 실험 브랜치는 이 클래스만 바꾸고 나머지는 건드리지 않는다.
 */
@Service
public class CouponIssueService {

	private final CouponRepository couponRepository;
	private final CouponIssueRepository couponIssueRepository;

	public CouponIssueService(
		CouponRepository couponRepository,
		CouponIssueRepository couponIssueRepository
	) {
		this.couponRepository = couponRepository;
		this.couponIssueRepository = couponIssueRepository;
	}

	@Transactional
	public void issue(Long couponId, Long memberId) {
		Coupon coupon = couponRepository.findById(couponId)
			.orElseThrow(() -> new CouponNotFoundException(couponId));

		if (coupon.isSoldOut()) {
			throw new SoldOutException(couponId);
		}

		// Dirty Checking 으로 트랜잭션 종료 시 UPDATE 된다.
		coupon.increaseIssuedCount();

		try {
			// saveAndFlush 로 INSERT 시점을 고정한다.
			// save 만 쓰면 커밋 시점에야 제약 위반이 드러나서 catch 위치가 모호해진다.
			couponIssueRepository.saveAndFlush(
				new CouponIssue(couponId, memberId, LocalDateTime.now())
			);
		} catch (DataIntegrityViolationException e) {
			// uk_coupon_issue_coupon_member 위반.
			// 예외로 트랜잭션이 롤백되므로 위의 issuedCount 증가도 함께 취소된다.
			// Redis 방식 브랜치는 이 복구가 자동으로 되지 않으므로 직접 되돌려야 한다.
			throw new DuplicateIssueException(couponId, memberId);
		}
	}
}
