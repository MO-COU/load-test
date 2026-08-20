package com.example.demo.benchmark;

import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.TimeUnit;
import org.springframework.stereotype.Component;

/**
 * 가장 단순한 형태의 인메모리 큐(순진한 구현).
 *
 * 크래시 시 큐에 남아있던 이벤트는 그대로 유실된다 — Redis Stream 같은
 * 영속 큐를 쓰지 않은 이유는 이 실험이 "동기 vs 비동기 DB 적재 자체의
 * 처리량·실패모드 비교"만을 목적으로 하기 때문이다(정합성·내구성
 * 비교는 analysis-notes.md 8장 참고, 이번 실험 범위 밖).
 *
 * 크기 제한(bound)을 두지 않았다 — 백프레셔 정책(가득 찼을 때 거부할지
 * 등)은 이번 실험의 관찰 대상이지 사전에 막을 대상이 아니다.
 */
@Component
public class AsyncIssueQueue {

	private final LinkedBlockingQueue<AsyncIssueEvent> queue = new LinkedBlockingQueue<>();

	public void enqueue(AsyncIssueEvent event) {
		queue.add(event);
	}

	/** 최대 timeoutMs 만큼 기다리다 이벤트가 없으면 null을 반환한다. */
	public AsyncIssueEvent poll(long timeoutMs) throws InterruptedException {
		return queue.poll(timeoutMs, TimeUnit.MILLISECONDS);
	}

	/** 큐 적체(lag) 관측용. 부하 도중 이 값이 계속 늘어나면 컨슈머가 못 따라가는 것이다. */
	public int size() {
		return queue.size();
	}
}