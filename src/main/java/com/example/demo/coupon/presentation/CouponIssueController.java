package com.example.demo.coupon.presentation;

import com.example.demo.common.exception.CouponNotFoundException;
import com.example.demo.common.exception.DuplicateIssueException;
import com.example.demo.common.exception.SoldOutException;
import com.example.demo.coupon.application.CouponIssueService;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 통일 사항. 실험 브랜치에서 이 클래스를 바꾸면 k6 스크립트와 어긋난다.
 *
 *   POST /issue?couponId=1&memberId=100
 *   200 ISSUED
 *   409 SOLD_OUT     재고 소진
 *   409 DUPLICATED   1인 1매 한도 위반
 *   404 NOT_FOUND    쿠폰 없음 (실험 중 발생하면 안 됨)
 *
 * 본문을 평문으로 두는 이유: 요청 대부분이 409라서 JSON 직렬화 비용을
 * 매 요청에 얹지 않기 위함이고, 6명이 각자 구현해도 편차가 날 여지가 없다.
 */
@RestController
public class CouponIssueController {

	private final CouponIssueService couponIssueService;

	public CouponIssueController(CouponIssueService couponIssueService) {
		this.couponIssueService = couponIssueService;
	}

	@PostMapping(value = "/issue", produces = MediaType.TEXT_PLAIN_VALUE)
	public ResponseEntity<String> issue(
		@RequestParam Long couponId,
		@RequestParam Long memberId
	) {
		try {
			couponIssueService.issue(couponId, memberId);
			return ResponseEntity.ok("ISSUED");
		} catch (SoldOutException e) {
			return ResponseEntity.status(HttpStatus.CONFLICT).body("SOLD_OUT");
		} catch (DuplicateIssueException e) {
			return ResponseEntity.status(HttpStatus.CONFLICT).body("DUPLICATED");
		} catch (CouponNotFoundException e) {
			return ResponseEntity.status(HttpStatus.NOT_FOUND).body("NOT_FOUND");
		}
	}
}
