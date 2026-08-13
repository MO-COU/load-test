package com.example.demo.coupon.infrastructure;

import java.time.LocalDateTime;

import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import com.example.demo.coupon.domain.CouponIssue;
import com.example.demo.coupon.domain.CouponIssueRepository;
import com.example.demo.coupon.domain.CouponRepository;

import lombok.RequiredArgsConstructor;


/**
 * Redis 발급 예약에 성공한 요청을 MySQL에 기록
 *
 * 이 메서드만 DB 트랜잭션으로 실행해서 커넥션 점유 시간을 줄임.
 */
@Component
@RequiredArgsConstructor
public class CouponIssueWriter {

	private final CouponRepository couponRepository;
	private final CouponIssueRepository couponIssueRepository;

	/*
	 * 기존 :
	 * coupon UPDATE 로 락 획득
	 * -> coupon_issue INSERT
	 * -> 커밋하여 락 해제
	 *
	 * 변경 :
	 * coupon_issue INSERT
	 * -> coupon UPDATE로 락 획득
	 * -> 곧바로 커밋하며 락 해제
	 */
	@Transactional
	public void write(Long couponId, Long memberId) {
		/*
		 * INSERT를 먼저 실행.
		 * 쿠폰 행 UPDATE를 마지막에 수행하면 해당 행의 락을 획득한 뒤
		 * 바로 커밋할 수 있어 락 점유 시간이 짧아짐.
		 */
		couponIssueRepository.saveAndFlush(
				new CouponIssue(couponId, memberId, LocalDateTime.now())
		);

		int updatedRows = couponRepository.increaseIssuedCount(couponId);

        if (updatedRows != 1) {
            throw new IllegalStateException(
                "Failed to increase issued count: coupon=" + couponId
            );
        }
	}
}







