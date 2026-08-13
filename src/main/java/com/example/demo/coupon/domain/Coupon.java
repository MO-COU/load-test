package com.example.demo.coupon.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "coupon")
public class Coupon {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	@Column(name = "coupon_id")
	private Long id;

	@Column(nullable = false)
	private String name;

	/** 총 재고. 실험 중 변하지 않는다. */
	@Column(name = "total_quantity", nullable = false)
	private int totalQuantity;

	/** 발급 수량. 초기화 대상은 이 값이다. */
	@Column(name = "issued_count", nullable = false)
	private int issuedCount;

	// coupon.version 컬럼은 스키마에 있지만 baseline은 매핑하지 않는다.
	// 낙관적 락 브랜치에서만 아래를 추가한다.
	//   @Version
	//   private Long version;

	protected Coupon() {
	}

	public Coupon(String name, int totalQuantity) {
		this.name = name;
		this.totalQuantity = totalQuantity;
		this.issuedCount = 0;
	}

	public boolean isSoldOut() {
		return issuedCount >= totalQuantity;
	}

	public void increaseIssuedCount() {
		issuedCount++;
	}

	public Long getId() {
		return id;
	}

	public String getName() {
		return name;
	}

	public int getTotalQuantity() {
		return totalQuantity;
	}

	public int getIssuedCount() {
		return issuedCount;
	}
}
