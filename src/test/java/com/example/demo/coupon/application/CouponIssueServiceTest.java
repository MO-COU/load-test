package com.example.demo.coupon.application;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.example.demo.common.exception.SoldOutException;
import com.example.demo.coupon.domain.Coupon;
import com.example.demo.coupon.domain.CouponIssueRepository;
import com.example.demo.coupon.domain.CouponRepository;
import java.util.Optional;
import org.junit.jupiter.api.Test;

class CouponIssueServiceTest {

	private final CouponRepository couponRepository = mock(CouponRepository.class);
	private final CouponIssueRepository couponIssueRepository = mock(CouponIssueRepository.class);
	private final CouponIssueService couponIssueService = new CouponIssueService(
		couponRepository,
		couponIssueRepository
	);

	@Test
	void 조건부_증가에_실패하면_품절로_처리한다() {
		when(couponRepository.findById(1L))
			.thenReturn(Optional.of(new Coupon("쿠폰", 1)));
		when(couponRepository.increaseIssuedCountIfAvailable(1L)).thenReturn(0);

		assertThatThrownBy(() -> couponIssueService.issue(1L, 100L))
			.isInstanceOf(SoldOutException.class);
		verifyNoInteractions(couponIssueRepository);
	}
}
