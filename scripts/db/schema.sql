CREATE TABLE IF NOT EXISTS members (
    member_id BIGINT NOT NULL AUTO_INCREMENT,
    PRIMARY KEY (member_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS coupons (
    coupon_id BIGINT NOT NULL AUTO_INCREMENT,
    name VARCHAR(255) NOT NULL,
    quantity INT NOT NULL,
    PRIMARY KEY (coupon_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS coupon_issues (
    coupon_issue_id BIGINT NOT NULL AUTO_INCREMENT,
    coupon_id BIGINT NOT NULL,
    member_id BIGINT NOT NULL,
    issued_at DATETIME(6) NOT NULL,
    PRIMARY KEY (coupon_issue_id),
    CONSTRAINT fk_coupon_issues_coupon FOREIGN KEY (coupon_id) REFERENCES coupons (coupon_id),
    CONSTRAINT fk_coupon_issues_member FOREIGN KEY (member_id) REFERENCES members (member_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE coupons CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE coupon_issues CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
