package com.mycom.myapp.coupon.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "coupons")
public class Coupon {

	@Id
	@GeneratedValue(strategy = GenerationType.IDENTITY)
	@Column(name = "coupon_id")
	private Long id;

	@Column(nullable = false)
	private String name;

	@Column(nullable = false)
	private int quantity;

	protected Coupon() {
	}

	public Coupon(String name, int quantity) {
		this.name = name;
		this.quantity = quantity;
	}

	public void decreaseQuantity() {
		quantity--;
	}

	public Long getId() {
		return id;
	}

	public String getName() {
		return name;
	}

	public int getQuantity() {
		return quantity;
	}
}
