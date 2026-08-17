package com.example.demo.coupon.application;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.demo.common.exception.DuplicateIssueException;
import com.example.demo.common.exception.SoldOutException;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * 정합성 통합 테스트. 전 브랜치 공통이며 수정하면 비교가 성립하지 않는다.
 * Redis 전용 단언은 해당 브랜치에서 추가한다.
 *
 * 전제: docker compose up -d 로 MySQL(3306), Redis(6379) 가 떠 있어야 한다.
 * main(baseline)은 동시성 제어가 없어 실패한다. 정상이다.
 */
@SpringBootTest
class CouponIssueConcurrencyTest {

	private static final long COUPON_ID = 1L;
	private static final int STOCK = 1000;
	private static final int MEMBER_POOL = 2000;  // 재고보다 많아야 품절이 발생한다
	private static final int THREADS = 100;       // 커넥션 풀(50)보다 커야 경합이 유지된다
	private static final int CLIENT_RETRY = 300;  // 서버가 포기하면 사용자가 다시 누르듯 재호출

	private final String stockKey = "coupon:stock:" + COUPON_ID;

	private static final ThreadFactory DAEMON = r -> {
		Thread t = new Thread(r);
		t.setDaemon(true);
		return t;
	};

	@Autowired private CouponIssueService couponIssueService;
	@Autowired private StringRedisTemplate redisTemplate;
	@Autowired private JdbcTemplate jdbcTemplate;

	@BeforeEach
	void reset() {
		jdbcTemplate.update("DELETE FROM coupon_issue");
		jdbcTemplate.update(
			"INSERT INTO coupon (coupon_id, name, total_quantity, issued_count, version) "
				+ "VALUES (?, '선착순 쿠폰', ?, 0, 0) "
				+ "ON DUPLICATE KEY UPDATE total_quantity = ?, issued_count = 0, version = 0",
			COUPON_ID, STOCK, STOCK);

		redisTemplate.delete(redisTemplate.keys("coupon:*"));
		redisTemplate.opsForValue().set(stockKey, String.valueOf(STOCK));
	}

	@Test
	@DisplayName("재고보다 많은 회원이 동시에 요청해도 재고만큼만 발급된다")
	void noOverIssue() throws InterruptedException {
		ExecutorService pool = Executors.newFixedThreadPool(THREADS, DAEMON);
		AtomicInteger success = new AtomicInteger();
		AtomicInteger soldOut = new AtomicInteger();
		AtomicInteger serverGiveUps = new AtomicInteger();
		AtomicInteger unresolved = new AtomicInteger();

		for (int member = 1; member <= MEMBER_POOL; member++) {
			long memberId = member;
			pool.submit(() -> issueWithClientRetry(memberId, success, soldOut, serverGiveUps, unresolved));
		}
		pool.shutdown();
		assertThat(pool.awaitTermination(180, TimeUnit.SECONDS))
			.as("제한 시간 내 종료").isTrue();

		System.out.printf("발급 %d / 품절 %d / 서버 포기 %d회 / 미해소 %d%n",
			success.get(), soldOut.get(), serverGiveUps.get(), unresolved.get());

		assertThat(issuedRows()).as("초과 발급 — coupon_issue 행 수").isEqualTo(STOCK);
		assertThat(duplicateMembers()).as("중복 발급 — 2건 이상 받은 회원 수").isZero();
	}

	/**
	 * 서버가 재시도 소진으로 포기(5xx)하면 사용자가 다시 누르듯 재호출한다.
	 * 재시도 상한이 있는 방식(optimistic, redis-watch)에서만 발동하고,
	 * 대기형·원자형은 첫 호출에 성공/품절로 끝나 루프를 돌지 않는다.
	 *
	 * 서버 포기 횟수는 관측값으로만 남긴다. 정합성 위반(초과 발급)이 아니라
	 * 가용성 문제이며, 실패율 자체는 EC2 k6 측정이 담당한다.
	 */
	private void issueWithClientRetry(long memberId, AtomicInteger success,
		AtomicInteger soldOut, AtomicInteger serverGiveUps, AtomicInteger unresolved) {
		for (int attempt = 0; attempt < CLIENT_RETRY; attempt++) {
			if (Thread.currentThread().isInterrupted()) {
				return;
			}
			try {
				couponIssueService.issue(COUPON_ID, memberId);
				success.incrementAndGet();
				return;
			} catch (SoldOutException e) {
				soldOut.incrementAndGet();
				return;
			} catch (DuplicateIssueException e) {
				// 회원이 전부 달라 정상 흐름에서는 오지 않는다.
				unresolved.incrementAndGet();
				return;
			} catch (RuntimeException e) {
				serverGiveUps.incrementAndGet();
			}
		}
		unresolved.incrementAndGet();
	}

	@Test
	@DisplayName("같은 회원이 동시에 여러 번 요청해도 1건만 발급된다")
	void noDuplicateIssue() throws InterruptedException {
		long memberId = 7L;
		ExecutorService pool = Executors.newFixedThreadPool(THREADS, DAEMON);
		// 전원을 세워뒀다가 동시에 출발시킨다. 순차 실행이면 경합이 만들어지지 않는다.
		CountDownLatch start = new CountDownLatch(1);
		CountDownLatch done = new CountDownLatch(THREADS);

		AtomicInteger success = new AtomicInteger();
		AtomicInteger duplicate = new AtomicInteger();
		AtomicInteger other = new AtomicInteger();

		for (int i = 0; i < THREADS; i++) {
			pool.submit(() -> {
				try {
					start.await();
					couponIssueService.issue(COUPON_ID, memberId);
					success.incrementAndGet();
				} catch (DuplicateIssueException e) {
					duplicate.incrementAndGet();
				} catch (InterruptedException e) {
					Thread.currentThread().interrupt();
				} catch (RuntimeException e) {
					other.incrementAndGet();
				} finally {
					done.countDown();
				}
			});
		}
		start.countDown();
		assertThat(done.await(60, TimeUnit.SECONDS)).as("제한 시간 내 종료").isTrue();
		pool.shutdownNow();

		System.out.printf("발급 %d / 중복 %d / 그 외 %d%n",
			success.get(), duplicate.get(), other.get());

		assertThat(issuedRows()).as("같은 회원의 발급 행 수").isEqualTo(1);
	}

	private long issuedRows() {
		return jdbcTemplate.queryForObject(
			"SELECT COUNT(*) FROM coupon_issue WHERE coupon_id = ?", Long.class, COUPON_ID);
	}

	private int duplicateMembers() {
		return jdbcTemplate.queryForObject(
			"SELECT COUNT(*) FROM (SELECT member_id FROM coupon_issue "
				+ "WHERE coupon_id = ? GROUP BY member_id HAVING COUNT(*) > 1) d",
			Integer.class, COUPON_ID);
	}
}
