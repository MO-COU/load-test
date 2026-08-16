package com.example.demo.coupon.infrastructure;

import java.time.LocalDateTime;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.example.demo.coupon.domain.CouponIssue;
import com.example.demo.coupon.domain.CouponIssueRepository;
import lombok.RequiredArgsConstructor;


/**
 * Redis 발급 예약에 성공한 요청을 MySQL에 기록
 *
 * Redis에서 재고와 중복 여부 판정
 * 쿠폰 카운터는 갱신하지 않고 coupon_issue INSERT만 수행.
 */
@Component
@RequiredArgsConstructor
public class CouponIssueWriter {

	private final CouponIssueRepository couponIssueRepository;

	@Transactional
	public void write(Long couponId, Long memberId) {
		couponIssueRepository.saveAndFlush(
				new CouponIssue(couponId, memberId, LocalDateTime.now())
		);

	}
}







