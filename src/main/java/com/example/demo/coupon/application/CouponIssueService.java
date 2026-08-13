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
 * 비관적 락 (SELECT ... FOR UPDATE)
 *
 * 쿠폰 행을 읽는 시점에 배타 락을 걸어, 재고 확인부터 증가까지를 직렬화한다.
 * 락은 트랜잭션 커밋 시점에 풀리므로 그 사이 다른 요청은 대기한다.
 *
 * baseline 대비 바뀐 것은 findById -> findWithLockById 한 줄뿐이다.
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
		// 여기서 배타 락을 획득한다. 이후 구간은 이 쿠폰에 대해 한 번에 하나만 실행된다.
		Coupon coupon = couponRepository.findWithLockById(couponId)
			.orElseThrow(() -> new CouponNotFoundException(couponId));

		if (coupon.isSoldOut()) {
			throw new SoldOutException(couponId);
		}

		// Dirty Checking 으로 트랜잭션 종료 시 UPDATE 된다.
		// 락 덕분에 다른 트랜잭션이 같은 값을 읽고 덮어쓰는 일이 없다.
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
