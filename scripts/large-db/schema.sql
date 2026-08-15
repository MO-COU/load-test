-- 대용량 성능 실험 전용 스키마.
-- 기존 동시성 실험의 scripts/db/schema.sql과 독립적으로 관리한다.

CREATE TABLE IF NOT EXISTS member (
    member_id  BIGINT      NOT NULL,
    created_at DATETIME(6) NOT NULL,
    PRIMARY KEY (member_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS coupon (
    coupon_id      BIGINT       NOT NULL AUTO_INCREMENT,
    name           VARCHAR(255) NOT NULL,
    total_quantity INT          NOT NULL,
    issued_count   INT          NOT NULL DEFAULT 0,
    version        BIGINT       NOT NULL DEFAULT 0,
    PRIMARY KEY (coupon_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS coupon_issue (
    coupon_issue_id BIGINT       NOT NULL AUTO_INCREMENT,
    coupon_id       BIGINT       NOT NULL,
    member_id       BIGINT       NOT NULL,
    status          VARCHAR(20)  NOT NULL,
    issued_at       DATETIME(6)  NOT NULL,
    PRIMARY KEY (coupon_issue_id),
    -- 무결성과 현재 발급 로직 호환을 위한 제약이다.
    UNIQUE KEY uk_coupon_issue_coupon_member (coupon_id, member_id),
    -- 회원별 쿠폰 조회의 WHERE member_id와 ORDER BY issued_at DESC를 함께 지원한다.
    KEY idx_coupon_issue_member_issued_at (member_id, issued_at DESC)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
