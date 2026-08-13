package com.mycom.myapp.common.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

@RestControllerAdvice
public class GlobalExceptionHandler {

	@ExceptionHandler({MemberNotFoundException.class, CouponNotFoundException.class})
	public ResponseEntity<ErrorResponse> handleNotFound(RuntimeException exception) {
		return ResponseEntity.status(HttpStatus.NOT_FOUND)
			.body(new ErrorResponse("NOT_FOUND", exception.getMessage()));
	}

	@ExceptionHandler(SoldOutException.class)
	public ResponseEntity<ErrorResponse> handleSoldOut(SoldOutException exception) {
		return ResponseEntity.status(HttpStatus.CONFLICT)
			.body(new ErrorResponse("SOLD_OUT", exception.getMessage()));
	}
}
