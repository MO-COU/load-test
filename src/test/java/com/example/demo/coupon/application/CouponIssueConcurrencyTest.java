package com.example.demo.coupon.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.example.demo.common.exception.DuplicateIssueException;
import com.example.demo.common.exception.OptimisticRetryExhaustedException;
import com.example.demo.common.exception.SoldOutException;
import com.example.demo.coupon.domain.CouponIssueRepository;
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
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.data.redis.core.StringRedisTemplate;

/**
 * 동시성·정합성 통합 테스트.
 *
 * README 판정 기준을 k6 대신 스레드 동시 요청으로 검증한다.
 *   - 초과 발급 없음 : issued_count == 재고
 *   - 중복 발급 없음 : 회원별 발급 ≤ 1
 *   - 정합성        : issued_count(카운터) == coupon_issue 행 수
 *
 * 전제: docker compose up -d 로 로컬 Redis(6379) + MySQL(3306)이 떠 있어야 한다.
 * (README 테스트 절차와 동일한 인프라를 그대로 쓴다.)
 */
@SpringBootTest
class CouponIssueConcurrencyTest {

	private static final long COUPON_ID = 1L;
	private static final int STOCK = 1000;         // data.sql 의 total_quantity 와 일치
	private static final int MEMBER_POOL = 2000;   // 재고보다 많은 회원 → 절반은 품절

	private final String stockKey = "coupon:stock:" + COUPON_ID;
	private final String issuedKey = "coupon:issued:" + COUPON_ID;

	// 데몬 스레드로 만들어, 테스트가 끝나면 남은 작업이 있어도 JVM 종료를 막지 않게 한다.
	private static final ThreadFactory DAEMON = r -> {
		Thread t = new Thread(r);
		t.setDaemon(true);
		return t;
	};

	@Autowired private CouponIssueService couponIssueService;
	@Autowired private CouponIssueRepository couponIssueRepository;
	@Autowired private StringRedisTemplate redisTemplate;
	@Autowired private JdbcTemplate jdbcTemplate;

	@BeforeEach
	void reset() {
		// DB 초기화: 발급 이력 비우고, 쿠폰을 재고 STOCK / issued_count 0 으로 맞춘다.
		jdbcTemplate.update("DELETE FROM coupon_issue");
		jdbcTemplate.update(
			"INSERT INTO coupon (coupon_id, name, total_quantity, issued_count, version) "
				+ "VALUES (?, '선착순 쿠폰', ?, 0, 0) "
				+ "ON DUPLICATE KEY UPDATE total_quantity = ?, issued_count = 0, version = 0",
			COUPON_ID, STOCK, STOCK);

		// Redis 초기화: 두 키를 지우고 재고를 STOCK 으로 세팅한다(README 의 SET coupon:stock:1 1000).
		redisTemplate.delete(stockKey);
		redisTemplate.delete(issuedKey);
		redisTemplate.opsForValue().set(stockKey, String.valueOf(STOCK));
	}

	@Test
	@DisplayName("서로 다른 회원들이 동시에 요청해도 재고만큼만 발급되고 정합성이 맞는다")
	void concurrentIssue_noOverIssue_noDuplicate() throws InterruptedException {
		int threads = 20;
		ExecutorService pool = Executors.newFixedThreadPool(threads, DAEMON);

		AtomicInteger success = new AtomicInteger();
		AtomicInteger soldOut = new AtomicInteger();
		AtomicInteger unexpected = new AtomicInteger();

		// 200개 요청을 20스레드 풀에 제출한다. 풀 크기만큼(20) 항상 동시 실행되므로
		// 공유 키(재고/발급 셋)에 대한 실제 경합이 발생한다.
		for (int member = 1; member <= MEMBER_POOL; member++) {
			long memberId = member;
			pool.submit(() -> issueWithClientRetry(memberId, success, soldOut, unexpected));
		}
		pool.shutdown();
		boolean finished = pool.awaitTermination(120, TimeUnit.SECONDS);
		pool.shutdownNow();
		assertThat(finished).as("모든 요청이 제한 시간 내 종료됐는지").isTrue();

		int issuedCount = jdbcTemplate.queryForObject(
			"SELECT issued_count FROM coupon WHERE coupon_id = ?", Integer.class, COUPON_ID);
		long issuedRows = couponIssueRepository.count();
		Integer duplicateMembers = jdbcTemplate.queryForObject(
			"SELECT COUNT(*) FROM (SELECT member_id FROM coupon_issue "
				+ "WHERE coupon_id = ? GROUP BY member_id HAVING COUNT(*) > 1) d",
			Integer.class, COUPON_ID);
		String remainingStock = redisTemplate.opsForValue().get(stockKey);

		// 예상 밖 오류(재시도 소진 등)는 없어야 한다 = README 의 "5xx 0건".
		assertThat(unexpected.get()).as("예상 밖 오류(500)").isZero();
		// 초과 발급 없음: 정확히 재고만큼만 발급.
		assertThat(success.get()).as("발급 성공 건수").isEqualTo(STOCK);
		assertThat(issuedCount).as("coupon.issued_count").isEqualTo(STOCK);
		// 정합성: 카운터 == 실제 행 수.
		assertThat(issuedRows).as("coupon_issue 행 수").isEqualTo(STOCK);
		// 중복 발급 없음.
		assertThat(duplicateMembers).as("2건 이상 발급된 회원 수").isZero();
		// 품절 처리된 나머지.
		assertThat(soldOut.get()).as("품절 응답 건수").isEqualTo(MEMBER_POOL - STOCK);
		// Redis 재고도 정확히 0.
		assertThat(remainingStock).as("Redis 잔여 재고").isEqualTo("0");
	}

	@Test
	@DisplayName("같은 회원이 동시에 여러 번 요청해도 1건만 발급된다 (1인 1매)")
	void concurrentDuplicate_onlyOneSucceeds() throws InterruptedException {
		int threads = 64;
		long memberId = 7L;
		ExecutorService pool = Executors.newFixedThreadPool(threads, DAEMON);
		CountDownLatch start = new CountDownLatch(1);
		CountDownLatch done = new CountDownLatch(threads);

		AtomicInteger success = new AtomicInteger();
		AtomicInteger duplicate = new AtomicInteger();
		AtomicInteger unexpected = new AtomicInteger();

		for (int i = 0; i < threads; i++) {
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
					unexpected.incrementAndGet();
				} finally {
					done.countDown();
				}
			});
		}

		start.countDown();
		done.await(30, TimeUnit.SECONDS);
		pool.shutdownNow();

		long rowsForMember = jdbcTemplate.queryForObject(
			"SELECT COUNT(*) FROM coupon_issue WHERE coupon_id = ? AND member_id = ?",
			Long.class, COUPON_ID, memberId);
		int issuedCount = jdbcTemplate.queryForObject(
			"SELECT issued_count FROM coupon WHERE coupon_id = ?", Integer.class, COUPON_ID);

		assertThat(unexpected.get()).as("예상 밖 오류(500)").isZero();
		assertThat(success.get()).as("성공 건수").isEqualTo(1);
		assertThat(duplicate.get()).as("중복 응답 건수").isEqualTo(threads - 1);
		assertThat(rowsForMember).as("해당 회원 발급 행 수").isEqualTo(1);
		assertThat(issuedCount).as("issued_count").isEqualTo(1);
	}

	@Test
	@DisplayName("재고가 0이면 SoldOutException 을 던진다")
	void soldOut_whenNoStock() {
		redisTemplate.opsForValue().set(stockKey, "0");

		assertThatThrownBy(() -> couponIssueService.issue(COUPON_ID, 1L))
			.isInstanceOf(SoldOutException.class);
	}

	/**
	 * 서버가 WATCH 재시도를 소진(OptimisticRetryExhaustedException)하면 클라이언트가 다시 시도하듯 재시도한다.
	 * 이렇게 하면 재고가 끝까지 소진되어 "초과 발급 없음"을 결정론적으로 검증할 수 있다.
	 * (재시도 소진 자체의 빈도는 k6 부하테스트에서 따로 관측한다.)
	 */
	private void issueWithClientRetry(long memberId,
		AtomicInteger success, AtomicInteger soldOut, AtomicInteger unexpected) {
		for (int attempt = 0; attempt < 300; attempt++) {
			if (Thread.currentThread().isInterrupted()) {
				return;  // 셧다운(인터럽트) 시 즉시 종료해 스레드가 안 죽는 일을 막는다.
			}
			try {
				couponIssueService.issue(COUPON_ID, memberId);
				success.incrementAndGet();
				return;
			} catch (SoldOutException e) {
				soldOut.incrementAndGet();
				return;
			} catch (DuplicateIssueException e) {
				// 서로 다른 회원만 쓰는 시나리오라 정상 흐름에선 오지 않는다.
				unexpected.incrementAndGet();
				return;
			} catch (OptimisticRetryExhaustedException e) {
				// WATCH 재시도 소진 → 클라이언트 재시도.
			}
		}
		unexpected.incrementAndGet();
	}
}