package com.example.demo.benchmark;

import java.time.LocalDateTime;

public record CouponIssueRow(long couponIssueId, long couponId, long memberId, String status, LocalDateTime issuedAt) {
}
