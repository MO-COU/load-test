package com.example.demo.benchmark;

/**
 * 비동기 적재 큐에 쌓이는 이벤트 하나.
 * INSERT는 신규 발급, MARK_USED는 상태를 USED로 바꾸는 요청이다.
 */
public record AsyncIssueEvent(EventType type, long couponId, long memberId) {

	public enum EventType {
		INSERT,
		MARK_USED
	}
}