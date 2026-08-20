package com.example.demo.benchmark;

import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.util.ArrayList;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * 큐를 비우며 배치로 DB에 반영하는 백그라운드 워커.
 *
 * BATCH_SIZE 만큼 모이거나 BATCH_INTERVAL_MS 가 지나면(둘 중 먼저 오는
 * 조건) 그때까지 모인 것을 한 트랜잭션으로 커밋한다. BATCH_SIZE=1 이면
 * 사실상 배치가 없는 것과 같다(매번 1건씩 바로 커밋) — 1단계(분리
 * 효과만 측정)와 2단계(배치 효과 측정)를 같은 코드로 전환값만 바꿔서
 * 돈다.
 *
 * 기본값 BATCH_SIZE=100, BATCH_INTERVAL_MS=100 을 고른 이유:
 *  - 크기(100): JDBC 배치 INSERT에서 통상 쓰이는 크기다. fsync 1번으로
 *    100행을 실어 날라 동기 대비 처리량 이득을 확실히 보여주기에
 *    충분히 크면서도, 한 트랜잭션이 100개 행의 잠금을 오래 쥐고 있는
 *    부작용(analysis-notes.md 7장 "여전히 안 풀릴 것")이 커지지 않는
 *    범위로 잡았다.
 *  - 시간(100ms): 요청이 뜸할 때 배치가 안 차서 무한정 기다리는 걸
 *    막는 상한이다. Kafka Connect/Debezium 류가 흔히 쓰는 수백 ms
 *    수준의 배치 윈도우와 비슷한 자릿수로 맞췄다.
 *  - 이 값 자체를 최적화하는 것은 이번 실험의 목적이 아니다(배치
 *    적용 여부에 따른 성능 개선 유무만 본다). 그래서 "효율적인 값을
 *    찾는 튜닝"은 하지 않고, 상식적으로 무난한 값 하나로 고정했다.
 */
@Component
public class AsyncCouponIssueConsumer {

	private static final Logger log = LoggerFactory.getLogger(AsyncCouponIssueConsumer.class);

	private final AsyncIssueQueue queue;
	private final BenchmarkCouponIssueService service;
	private final int batchSize;
	private final long batchIntervalMs;

	private Thread worker;
	private volatile boolean running = true;

	public AsyncCouponIssueConsumer(
		AsyncIssueQueue queue,
		BenchmarkCouponIssueService service,
		@Value("${benchmark.async.batch-size:100}") int batchSize,
		@Value("${benchmark.async.batch-interval-ms:100}") long batchIntervalMs
	) {
		this.queue = queue;
		this.service = service;
		this.batchSize = batchSize;
		this.batchIntervalMs = batchIntervalMs;
	}

	@PostConstruct
	void start() {
		worker = new Thread(this::run, "async-coupon-consumer");
		worker.setDaemon(true);
		worker.start();
	}

	@PreDestroy
	void stop() {
		running = false;
		if (worker != null) {
			worker.interrupt();
		}
	}

	private void run() {
		List<AsyncIssueEvent> batch = new ArrayList<>(batchSize);
		long batchStartedAt = System.currentTimeMillis();

		while (running) {
			long elapsed = System.currentTimeMillis() - batchStartedAt;
			long waitMs = Math.max(1, batchIntervalMs - elapsed);

			AsyncIssueEvent event;
			try {
				event = queue.poll(waitMs);
			} catch (InterruptedException e) {
				Thread.currentThread().interrupt();
				break;
			}

			if (event != null) {
				batch.add(event);
			}

			boolean full = batch.size() >= batchSize;
			boolean timedOut = System.currentTimeMillis() - batchStartedAt >= batchIntervalMs;

			if (!batch.isEmpty() && (full || timedOut)) {
				flush(batch);
				batch = new ArrayList<>(batchSize);
				batchStartedAt = System.currentTimeMillis();
			} else if (batch.isEmpty() && timedOut) {
				batchStartedAt = System.currentTimeMillis();
			}
		}

		// 정상 종료(앱 셧다운) 시 마지막으로 모여있던 건 마저 반영한다.
		// 하드 크래시(kill -9, 정전 등)면 이 코드조차 못 돌고 그대로 유실된다 — 인메모리 큐의 알려진 한계.
		if (!batch.isEmpty()) {
			flush(batch);
		}
	}

	/**
	 * 배치 하나가 실패해도(예: UNIQUE 제약 위반) 컨슈머 스레드 자체는
	 * 죽지 않고 다음 배치를 계속 처리한다. 이번 실험은 배치 유무에 따른
	 * 성능 비교가 목적이지 실패한 배치의 재처리·정합성 보장까지는
	 * 다루지 않으므로, 실패한 배치는 로그만 남기고 버린다(그 안에 있던
	 * 건들은 유실됨 — analysis-notes.md 8장에서 이미 언급한 인메모리
	 * 큐의 알려진 한계와 같은 종류).
	 */
	private void flush(List<AsyncIssueEvent> batch) {
		List<AsyncIssueEvent> inserts = new ArrayList<>();
		List<AsyncIssueEvent> markUsed = new ArrayList<>();
		for (AsyncIssueEvent event : batch) {
			if (event.type() == AsyncIssueEvent.EventType.INSERT) {
				inserts.add(event);
			} else {
				markUsed.add(event);
			}
		}
		try {
			service.flushBatch(inserts, markUsed);
		} catch (RuntimeException e) {
			log.error("배치 반영 실패, {}건 유실(insert={}, markUsed={}): {}",
				batch.size(), inserts.size(), markUsed.size(), e.getMessage());
		}
	}
}