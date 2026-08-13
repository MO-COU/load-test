package com.example.demo.coupon.domain;

import jakarta.persistence.LockModeType;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;

public interface CouponRepository extends JpaRepository<Coupon, Long> {

	/**
	 * SELECT ... FOR UPDATE 로 쿠폰 행에 배타 락을 건다.
	 * 락을 잡은 트랜잭션이 커밋될 때까지 다른 트랜잭션은 이 행을 읽지 못하고 대기하므로,
	 * 재고 확인과 증가가 하나의 원자적 구간이 된다.
	 */
	@Lock(LockModeType.PESSIMISTIC_WRITE)
	Optional<Coupon> findWithLockById(Long couponId);
}
