package com.mycom.myapp.coupon.domain;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class CouponTest {

	@Test
	void 재고를_하나_차감한다() {
		Coupon coupon = new Coupon("선착순 쿠폰", 1);

		coupon.decreaseQuantity();

		assertEquals(0, coupon.getQuantity());
	}
}
