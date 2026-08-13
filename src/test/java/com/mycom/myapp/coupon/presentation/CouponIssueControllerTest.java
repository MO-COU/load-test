package com.mycom.myapp.coupon.presentation;

import static org.mockito.Mockito.when;
import static org.springframework.http.MediaType.APPLICATION_JSON;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.mycom.myapp.coupon.application.CouponIssueService;
import com.mycom.myapp.coupon.domain.Coupon;
import com.mycom.myapp.coupon.domain.CouponIssue;
import com.mycom.myapp.member.domain.Member;
import java.time.LocalDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

class CouponIssueControllerTest {

	private CouponIssueService couponIssueService;
	private MockMvc mockMvc;

	@BeforeEach
	void setUp() {
		couponIssueService = Mockito.mock(CouponIssueService.class);
		mockMvc = MockMvcBuilders.standaloneSetup(new CouponIssueController(couponIssueService)).build();
	}

	@Test
	void 쿠폰을_발급하면_발급_정보와_함께_201을_반환한다() throws Exception {
		Coupon coupon = new Coupon("선착순 쿠폰", 9);
		Member member = new Member();
		CouponIssue couponIssue = new CouponIssue(coupon, member, LocalDateTime.of(2026, 8, 13, 10, 0));
		ReflectionTestUtils.setField(coupon, "id", 2L);
		ReflectionTestUtils.setField(member, "memberId", 1L);
		ReflectionTestUtils.setField(couponIssue, "couponIssueId", 3L);
		when(couponIssueService.issue(2L, 1L)).thenReturn(couponIssue);

		mockMvc.perform(post("/api/coupons/2/issue")
				.contentType(APPLICATION_JSON)
				.content("{\"memberId\":1}"))
			.andExpect(status().isCreated())
			.andExpect(jsonPath("$.couponIssueId").value(3))
			.andExpect(jsonPath("$.couponId").value(2))
			.andExpect(jsonPath("$.memberId").value(1));
	}
}
