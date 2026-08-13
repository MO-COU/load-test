package com.mycom.myapp.coupon.application;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.mycom.myapp.coupon.domain.Coupon;
import com.mycom.myapp.coupon.domain.CouponIssue;
import com.mycom.myapp.coupon.domain.CouponIssueRepository;
import com.mycom.myapp.coupon.domain.CouponRepository;
import com.mycom.myapp.common.exception.SoldOutException;
import com.mycom.myapp.member.domain.Member;
import com.mycom.myapp.member.domain.MemberRepository;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class CouponIssueServiceTest {

	@Mock
	private MemberRepository memberRepository;

	@Mock
	private CouponRepository couponRepository;

	@Mock
	private CouponIssueRepository couponIssueRepository;

	@InjectMocks
	private CouponIssueService couponIssueService;

	@Test
	void 발급하면_재고를_차감하고_발급_이력을_저장한다() {
		Member member = new Member();
		Coupon coupon = new Coupon("선착순 쿠폰", 10);
		when(memberRepository.findById(1L)).thenReturn(Optional.of(member));
		when(couponRepository.findById(2L)).thenReturn(Optional.of(coupon));

		couponIssueService.issue(2L, 1L);

		assertEquals(9, coupon.getQuantity());
		verify(couponIssueRepository).save(any(CouponIssue.class));
	}

	@Test
	void 재고가_없으면_품절_예외를_발생시킨다() {
		when(memberRepository.findById(1L)).thenReturn(Optional.of(new Member()));
		when(couponRepository.findById(2L)).thenReturn(Optional.of(new Coupon("선착순 쿠폰", 0)));

		assertThrows(SoldOutException.class, () -> couponIssueService.issue(2L, 1L));
	}
}
