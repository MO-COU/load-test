package com.example.demo.coupon.domain;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CouponRepository extends JpaRepository<Coupon, Long> {

	@Modifying
	@Query("update Coupon c set c.issuedCount = c.issuedCount + 1 where c.id = :couponId")
	void increaseIssuedCount(@Param("couponId") Long couponId);
}
