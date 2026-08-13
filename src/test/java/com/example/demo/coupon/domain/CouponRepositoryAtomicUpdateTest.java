package com.example.demo.coupon.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

@SpringBootTest
@Transactional
class CouponRepositoryAtomicUpdateTest {

	@Autowired
	private CouponRepository couponRepository;

	@Test
	void 재고가_남아_있으면_한_건을_원자적으로_증가한다() {
		int updated = couponRepository.increaseIssuedCountIfAvailable(1L);

		assertThat(updated).isEqualTo(1);
	}
}
