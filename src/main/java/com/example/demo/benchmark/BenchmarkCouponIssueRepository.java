package com.example.demo.benchmark;

import java.time.LocalDateTime;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class BenchmarkCouponIssueRepository {

	private final JdbcTemplate jdbcTemplate;

	public BenchmarkCouponIssueRepository(JdbcTemplate jdbcTemplate) {
		this.jdbcTemplate = jdbcTemplate;
	}

	public List<CouponIssueRow> findByMemberId(long memberId) {
		return jdbcTemplate.query(
			"SELECT coupon_issue_id, coupon_id, member_id, status, issued_at " +
				"FROM coupon_issue WHERE member_id = ? ORDER BY issued_at DESC",
			(rs, rowNum) -> new CouponIssueRow(
				rs.getLong("coupon_issue_id"), rs.getLong("coupon_id"), rs.getLong("member_id"),
				rs.getString("status"), rs.getObject("issued_at", LocalDateTime.class)
			),
			memberId
		);
	}

	public int insert(long couponId, long memberId) {
		return jdbcTemplate.update(
			"INSERT INTO coupon_issue (coupon_id, member_id, status, issued_at) VALUES (?, ?, 'ISSUED', NOW(6))",
			couponId, memberId
		);
	}

	public int markUsed(long couponId, long memberId) {
		return jdbcTemplate.update(
			"UPDATE coupon_issue SET status = 'USED' WHERE coupon_id = ? AND member_id = ? AND status = 'ISSUED'",
			couponId, memberId
		);
	}

	public List<CouponIssueSummary> summarize() {
		return jdbcTemplate.query(
			"SELECT coupon_id, status, COUNT(*) AS issue_count FROM coupon_issue GROUP BY coupon_id, status ORDER BY coupon_id, status",
			(rs, rowNum) -> new CouponIssueSummary(
				rs.getLong("coupon_id"), rs.getString("status"), rs.getLong("issue_count")
			)
		);
	}
}
