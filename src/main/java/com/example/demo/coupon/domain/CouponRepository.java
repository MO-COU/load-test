package com.example.demo.coupon.domain;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CouponRepository extends JpaRepository<Coupon, Long> {
	// 재고가 남아 있을 때만 발급 수를 증가시킨다.
	@Modifying(clearAutomatically = true)
	@Query("""
		    update Coupon c
		       set c.issuedCount = c.issuedCount + 1
		     where c.id = :couponId
		       and c.issuedCount < c.totalQuantity
		    """)
	int increaseIssuedCountIfAvailable(@Param("couponId") Long couponId);
}
