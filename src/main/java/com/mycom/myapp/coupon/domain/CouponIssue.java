package com.mycom.myapp.coupon.domain;

import com.mycom.myapp.member.domain.Member;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

@Entity
@Table(name = "coupon_issues")
public class CouponIssue {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	private Long couponIssueId;

	@ManyToOne(optional = false)
	@JoinColumn(name = "coupon_id")
	private Coupon coupon;

	@ManyToOne(optional = false)
	@JoinColumn(name = "member_id")
	private Member member;

	private LocalDateTime issuedAt;

	protected CouponIssue() {
	}

	public CouponIssue(Coupon coupon, Member member, LocalDateTime issuedAt) {
		this.coupon = coupon;
		this.member = member;
		this.issuedAt = issuedAt;
	}

	public Long getCouponIssueId() {
		return couponIssueId;
	}

	public Coupon getCoupon() {
		return coupon;
	}

	public Member getMember() {
		return member;
	}

	public LocalDateTime getIssuedAt() {
		return issuedAt;
	}
}
