package com.example.demo.coupon.application;

import com.example.demo.common.exception.DuplicateIssueException;
import com.example.demo.common.exception.SoldOutException;
import com.example.demo.coupon.domain.CouponIssue;
import com.example.demo.coupon.domain.CouponIssueRepository;
import com.example.demo.coupon.domain.CouponRepository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;
import org.springframework.data.redis.core.RedisOperations;
import org.springframework.data.redis.core.SessionCallback;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 낙관적 락(Redis WATCH / MULTI / EXEC) 기반 쿠폰 발급.
 *
 *   1. Redis 에서 재고와 1인1매를 먼저 확정한다(품절·중복이면 예외, WATCH 충돌이면 재시도).
 *   2. 확정되면 같은 결과를 DB(coupon_issue INSERT + issued_count 증가)에 기록한다.
 *      DB 반영이 실패하면 Redis 예약(DECR/SADD)을 손으로 되돌린다(INCR/SREM).
 *
 * Spring 메서드 ↔ Redis 명령: get→GET, isMember→SISMEMBER, decrement→DECR,
 *   add→SADD, increment→INCR(DECR 보상), remove→SREM(SADD 보상)
 *
 * 응답 계약(Controller 고정): 성공은 void, 품절은 SoldOutException(409),
 *   중복은 DuplicateIssueException(409).
 */
@Service
public class CouponIssueService {

	private final StringRedisTemplate redisTemplate;
	private final CouponRepository couponRepository;
	private final CouponIssueRepository couponIssueRepository;
	private final TransactionTemplate transactionTemplate;

	private static final int MAX_RETRY = 5;

	public CouponIssueService(
		StringRedisTemplate redisTemplate,
		CouponRepository couponRepository,
		CouponIssueRepository couponIssueRepository,
		PlatformTransactionManager transactionManager
	) {
		this.redisTemplate = redisTemplate;
		this.couponRepository = couponRepository;
		this.couponIssueRepository = couponIssueRepository;
		// INSERT + 증가를 한 트랜잭션으로 묶기 위한 것. @Transactional 을 이 클래스 내부에서
		// self-invocation 하면 프록시를 우회해 트랜잭션이 안 걸리므로 TransactionTemplate 을 쓴다.
		this.transactionTemplate = new TransactionTemplate(transactionManager);
	}

	public void issue(Long couponId, Long memberId) {
		String stockKey = "coupon:stock:" + couponId;
		String issuedKey = "coupon:issued:" + couponId;
		String memberIdStr = String.valueOf(memberId);

		for (int attempt = 0; attempt < MAX_RETRY; attempt++) {
			// reserveInRedis: 예약 성공이면 true, WATCH 충돌이면 false(재시도), 품절·중복이면 예외.
			if (reserveInRedis(stockKey, issuedKey, memberIdStr, couponId, memberId)) {
				persist(couponId, memberId, stockKey, issuedKey, memberIdStr);
				return;
			}
			sleepBeforeRetry();
		}

		// WATCH 충돌이 MAX_RETRY 안에 안 풀림. 숨기지 않고 5xx 로 드러낸다.
		// (고경합에서 WATCH 방식의 한계를 보여주는 측정값 그 자체다.)
		throw new IllegalStateException(
			"optimistic retry exhausted: coupon=" + couponId + ", member=" + memberId);
	}

	/**
	 * WATCH → 조건 확인 → MULTI/EXEC 로 Redis 상의 예약을 확정한다.
	 * @return 예약 성공이면 true, WATCH 충돌(EXEC null)이면 false
	 */
	private boolean reserveInRedis(String stockKey, String issuedKey,
		String memberIdStr, Long couponId, Long memberId) {

		Boolean reserved = redisTemplate.execute(new SessionCallback<Boolean>() {
			@Override
			@SuppressWarnings("unchecked")
			public Boolean execute(RedisOperations operations) {
				// WATCH: 이 두 키가 EXEC 전에 바뀌면 트랜잭션을 무효화한다.
				operations.watch(List.of(stockKey, issuedKey));

				String stockValue = (String) operations.opsForValue().get(stockKey);
				if (stockValue == null || Long.parseLong(stockValue) <= 0) {
					operations.unwatch();
					throw new SoldOutException(couponId);
				}

				if (Boolean.TRUE.equals(operations.opsForSet().isMember(issuedKey, memberIdStr))) {
					operations.unwatch();
					throw new DuplicateIssueException(couponId, memberId);
				}

				// 아래 두 명령은 큐에 쌓였다가 EXEC 시점에 원자적으로 함께 적용된다.
				operations.multi();
				operations.opsForValue().decrement(stockKey);       // DECR 재고 차감
				operations.opsForSet().add(issuedKey, memberIdStr);  // SADD 회원 등록
				List<Object> execResult = operations.exec();

				// EXEC 가 null 이면 WATCH 한 키가 그새 바뀐 것 → 큐잉된 DECR/SADD 는 적용 안 됨.
				// 예약 자체가 안 됐으므로 보상도 필요 없다.
				return execResult != null && !execResult.isEmpty();
			}
		});

		return Boolean.TRUE.equals(reserved);
	}

	/**
	 * Redis 예약을 DB 에 기록한다(INSERT + issued_count 증가를 한 트랜잭션으로).
	 * clean run 에서는 Redis 가 중복·품절을 이미 걸렀으므로 여기서 실패할 일이 없지만,
	 * 만약 실패(드리프트 등)하면 DB 는 트랜잭션이 롤백하고 Redis 는 손으로 되돌린다.
	 */
	private void persist(Long couponId, Long memberId,
		String stockKey, String issuedKey, String memberIdStr) {
		try {
			transactionTemplate.executeWithoutResult(status -> {
				couponIssueRepository.save(new CouponIssue(couponId, memberId, LocalDateTime.now()));
				couponRepository.increaseIssuedCount(couponId);
			});
		} catch (RuntimeException e) {
			// DB 반영 실패 → 방금 잡은 Redis 예약을 원복(INCR + SREM)하고 예외를 전파한다.
			redisTemplate.opsForValue().increment(stockKey);          // INCR: DECR 보상
			redisTemplate.opsForSet().remove(issuedKey, memberIdStr); // SREM: SADD 보상
			throw e;
		}
	}

	private void sleepBeforeRetry() {
		try {
			Thread.sleep(5 + ThreadLocalRandom.current().nextInt(15));
		} catch (InterruptedException e) {
			Thread.currentThread().interrupt();
		}
	}
}