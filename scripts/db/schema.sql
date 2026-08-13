-- 6개 실험 브랜치가 공유하는 스키마. 브랜치별로 수정하지 않는다.
-- 최초 1회만 실행된다(docker-entrypoint-initdb.d).

CREATE TABLE IF NOT EXISTS coupon (
    coupon_id      BIGINT       NOT NULL AUTO_INCREMENT,
    name           VARCHAR(255) NOT NULL,
    -- 총 재고. 실험 중 변하지 않는다.
    total_quantity INT          NOT NULL,
    -- 발급 수량. 초기화 대상은 이 값이다.
    issued_count   INT          NOT NULL DEFAULT 0,
    -- 낙관적 락 브랜치에서만 사용하지만, 스키마를 공유하기 위해 모두 갖는다.
    version        BIGINT       NOT NULL DEFAULT 0,
    PRIMARY KEY (coupon_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS coupon_issue (
    coupon_issue_id BIGINT      NOT NULL AUTO_INCREMENT,
    coupon_id       BIGINT      NOT NULL,
    member_id       BIGINT      NOT NULL,
    issued_at       DATETIME(6) NOT NULL,
    PRIMARY KEY (coupon_issue_id),
    -- 1인 1매 한도의 최종 방어선. 애플리케이션 로직이 새어도 DB가 막는다.
    UNIQUE KEY uk_coupon_issue_coupon_member (coupon_id, member_id)
) DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- FK를 걸지 않는 이유:
-- InnoDB는 FK가 있는 자식 테이블에 INSERT할 때 부모 행에 shared lock을 건다.
-- 모든 요청이 coupon_id=1 한 행에 몰리므로, FK 대기가 락 전략 차이와 뒤섞여
-- 측정값을 오염시킨다. member 테이블도 같은 이유와 핫패스 SELECT 제거를 위해 두지 않는다.
