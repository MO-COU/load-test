package com.example.demo.coupon.application;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.CannotCreateTransactionException;

import com.example.demo.common.exception.CouponNotFoundException;
import com.example.demo.common.exception.DuplicateIssueException;
import com.example.demo.common.exception.SoldOutException;
import com.example.demo.coupon.domain.CouponRepository;
import com.example.demo.coupon.infrastructure.CouponIssueWriter;
import com.example.demo.coupon.infrastructure.RedisCouponIssueGateway;
import com.example.demo.coupon.infrastructure.RedisCouponIssueGateway.ReservationResult;

import lombok.RequiredArgsConstructor;

/**
 * Redis Lua 기반 쿠폰 발급
 * Redis 에서 중복 확인과 재고 차감을 원자적으로 처리
 * 발급 예약에 성공한 요청만 MySQL에 저장.
 * MySQL 저장에 실패하면 Redis 발급 예약을 보상.
 */
@Service
@RequiredArgsConstructor
public class CouponIssueService {

	private static final int MAX_DB_WRITE_ATTEMPTS = 2;

	private final CouponRepository couponRepository;
	private final RedisCouponIssueGateway redisCouponIssueGateway;
	private final CouponIssueWriter couponIssueWriter;

	public void issue(Long couponId, Long memberId) {

		/*
		 * Lua 스크립트에서 다음 작업을 원자적으로 처리.
		 * 1. 중복 발급 확인
		 * 2. 재고 확인
		 * 3. 재고 차감
		 * 4. 발급 회원 등록
		 */

		ReservationResult result = redisCouponIssueGateway.reserve(couponId, memberId);
		validateReservation(result, couponId, memberId);

		try {
//			couponIssueWriter.write(couponId, memberId);
			writeWithRetry(couponId, memberId);
			// Redis 예약 성공
			// -> DB Writer 첫 시도 - 성공: 완료
			// 커넥션 획득 실패 : 한 번 재시도 - 성공 : 완료, 재실패 : Redis 보상 후 500

		} catch (DataIntegrityViolationException e) {

			// Redis 복구
			redisCouponIssueGateway.compensate(couponId, memberId);
			throw new DuplicateIssueException(couponId, memberId);
		} catch (RuntimeException e) {
			/*
			 * UNIQUE 제약 외의 DB 오류가 발생한 경우에도
			 * Redis 재고와 발급 회원 정보를 복구
			 */
			redisCouponIssueGateway.compensate(couponId, memberId);
			throw e;
		}
	}

	/**
	 * Redis가 DB 처리 속도보다 빠르게 발급을 승인하면 커넥션 풀이 일시적 포화 가능
	 *
	 * 트랜잭션 생성에 실패한 경우에는 아직 SQL이 실행되지 않았으므로 DB 저장만 제한적으로 재시도.
	 */

	private void writeWithRetry(Long couponId, Long memberId) {
	    CannotCreateTransactionException lastException = null;

	    for (int attempt = 1; attempt <= MAX_DB_WRITE_ATTEMPTS; attempt++) {
	        try {
	            couponIssueWriter.write(couponId, memberId);
	            return;
	        } catch (CannotCreateTransactionException e) {
	            lastException = e;
	        }
	    }

	    throw lastException;
	}

	 /**
     * Redis Lua 실행 결과를 애플리케이션 예외로 변환.
     */
    private void validateReservation(
        ReservationResult result,
        Long couponId,
        Long memberId
    ) {
        switch (result) {
            case SUCCESS -> {
                return;
            }
            case SOLD_OUT ->
                throw new SoldOutException(couponId);
            case DUPLICATED ->
                throw new DuplicateIssueException(couponId, memberId);
            case STOCK_NOT_INITIALIZED -> {

                if (!couponRepository.existsById(couponId)) {// 재고 키가 없을 때만 DB 확인
                    throw new CouponNotFoundException(couponId);
                }

                throw new IllegalStateException(
                    "Redis stock is not initialized: coupon=" + couponId
                );
            }
        }
    }
}
