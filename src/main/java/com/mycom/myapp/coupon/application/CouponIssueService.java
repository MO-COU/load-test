package com.mycom.myapp.coupon.application;

import com.mycom.myapp.common.exception.CouponNotFoundException;
import com.mycom.myapp.common.exception.MemberNotFoundException;
import com.mycom.myapp.common.exception.SoldOutException;
import com.mycom.myapp.coupon.domain.Coupon;
import com.mycom.myapp.coupon.domain.CouponIssue;
import com.mycom.myapp.coupon.domain.CouponIssueRepository;
import com.mycom.myapp.coupon.domain.CouponRepository;
import com.mycom.myapp.member.domain.Member;
import com.mycom.myapp.member.domain.MemberRepository;
import java.time.LocalDateTime;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class CouponIssueService {

	private final MemberRepository memberRepository;
	private final CouponRepository couponRepository;
	private final CouponIssueRepository couponIssueRepository;

	public CouponIssueService(
		MemberRepository memberRepository,
		CouponRepository couponRepository,
		CouponIssueRepository couponIssueRepository
	) {
		this.memberRepository = memberRepository;
		this.couponRepository = couponRepository;
		this.couponIssueRepository = couponIssueRepository;
	}

	@Transactional
	public CouponIssue issue(Long couponId, Long memberId) {
		Member member = memberRepository.findById(memberId)
			.orElseThrow(() -> new MemberNotFoundException(memberId));
		Coupon coupon = couponRepository.findById(couponId)
			.orElseThrow(() -> new CouponNotFoundException(couponId));

		if (coupon.getQuantity() <= 0) {
			throw new SoldOutException(couponId);
		}

		coupon.decreaseQuantity();
		CouponIssue couponIssue = new CouponIssue(coupon, member, LocalDateTime.now());
		return couponIssueRepository.save(couponIssue);
	}
}
