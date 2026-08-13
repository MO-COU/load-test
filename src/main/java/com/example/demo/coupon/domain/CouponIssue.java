package com.example.demo.coupon.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;

/**
 * FK와 member 테이블이 없으므로 연관관계 매핑 대신 식별자를 그대로 들고 있다.
 * 발급 1건마다 엔티티를 더 조회하지 않기 위한 선택이기도 하다.
 */
@Entity
@Table(name = "coupon_issue")
public class CouponIssue {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	@Column(name = "coupon_issue_id")
	private Long id;

	@Column(name = "coupon_id", nullable = false)
	private Long couponId;

	@Column(name = "member_id", nullable = false)
	private Long memberId;

	@Column(name = "issued_at", nullable = false)
	private LocalDateTime issuedAt;

	protected CouponIssue() {
	}

	public CouponIssue(Long couponId, Long memberId, LocalDateTime issuedAt) {
		this.couponId = couponId;
		this.memberId = memberId;
		this.issuedAt = issuedAt;
	}

	public Long getId() {
		return id;
	}

	public Long getCouponId() {
		return couponId;
	}

	public Long getMemberId() {
		return memberId;
	}

	public LocalDateTime getIssuedAt() {
		return issuedAt;
	}
}
