package com.example.demo.coupon.application;

import com.example.demo.common.exception.CouponNotFoundException;
import com.example.demo.common.exception.DuplicateIssueException;
import com.example.demo.common.exception.SoldOutException;
import com.example.demo.coupon.domain.Coupon;
import com.example.demo.coupon.domain.CouponIssue;
import com.example.demo.coupon.domain.CouponIssueRepository;
import com.example.demo.coupon.domain.CouponRepository;
import java.time.LocalDateTime;
import java.util.concurrent.ThreadLocalRandom;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 낙관적 락: Coupon.version 으로 write 시점의 충돌만 감지한다.
 *
 * findById는 락을 걸지 않으므로 baseline과 마찬가지로 여러 트랜잭션이
 * 같은 issuedCount를 동시에 읽을 수 있다. 다른 점은 커밋 시점이다.
 * UPDATE ... WHERE coupon_id=? AND version=? 이 0행을 갱신하면
 * 버전이 이미 바뀐 것이므로 Hibernate가 실패시키고, 여기서 잡아 재시도한다.
 * 결과적으로 초과 발급은 막히지만, 경합이 클수록 재시도 횟수가 늘어난다.
 *
 * @Transactional 메서드를 같은 클래스에서 self-invocation 하면 프록시를
 * 타지 않아 트랜잭션이 걸리지 않으므로, 재시도마다 새 트랜잭션이 필요한
 * 이 구조에서는 TransactionTemplate으로 직접 경계를 잡는다.
 */
@Service
public class CouponIssueService {

	private static final int MAX_RETRY = 5;	// 재시도 요청 5회

	private final CouponRepository couponRepository;
	private final CouponIssueRepository couponIssueRepository;
	private final TransactionTemplate transactionTemplate;	// 새 트랜잭션을 위함

	public CouponIssueService(
		CouponRepository couponRepository,
		CouponIssueRepository couponIssueRepository,
		PlatformTransactionManager transactionManager
	) {
		this.couponRepository = couponRepository;
		this.couponIssueRepository = couponIssueRepository;
		this.transactionTemplate = new TransactionTemplate(transactionManager);
	}

	public void issue(Long couponId, Long memberId) {
		ObjectOptimisticLockingFailureException lastFailure = null;

		for (int attempt = 0; attempt < MAX_RETRY; attempt++) {
			try {
				transactionTemplate.executeWithoutResult(
					status -> issueInNewTransaction(couponId, memberId)
				);
				return;
			} catch (ObjectOptimisticLockingFailureException e) {
				// version 충돌. 재고/중복 여부는 아직 확정되지 않았으므로 재시도한다.
				lastFailure = e;
				// 통일 사항: redis-watch 와 동일한 백오프. 무작위로 흩어져야
				// 실패한 요청들이 같은 시점에 다시 몰리지 않는다.
				try {
					Thread.sleep(5 + ThreadLocalRandom.current().nextInt(15));
				} catch (InterruptedException ie) {
					Thread.currentThread().interrupt();
					break;
				}
			}
		}

		// 재시도 한도 초과. 컨트롤러가 이 예외를 따로 잡지 않으므로 5xx로 응답된다.
		throw lastFailure;
	}

	private void issueInNewTransaction(Long couponId, Long memberId) {
		Coupon coupon = couponRepository.findById(couponId)
			.orElseThrow(() -> new CouponNotFoundException(couponId));

		if (coupon.isSoldOut()) {
			throw new SoldOutException(couponId);
		}

		// Dirty Checking 으로 트랜잭션 종료 시 UPDATE 된다.
		// version이 그 사이 바뀌었으면 이 UPDATE가 0행을 갱신하고 예외가 던져진다.
		coupon.increaseIssuedCount();

		try {
			// saveAndFlush 로 INSERT/UPDATE 시점을 고정한다.
			// save 만 쓰면 커밋 시점에야 제약/버전 위반이 드러나서 catch 위치가 모호해진다.
			couponIssueRepository.saveAndFlush(
				new CouponIssue(couponId, memberId, LocalDateTime.now())
			);
		} catch (DataIntegrityViolationException e) {
			// uk_coupon_issue_coupon_member 위반.
			// 예외로 트랜잭션이 롤백되므로 위의 issuedCount 증가도 함께 취소된다.
			throw new DuplicateIssueException(couponId, memberId);
		}
	}
}
