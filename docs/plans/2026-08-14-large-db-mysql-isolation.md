# Large DB MySQL Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 기존 동시성 실험 DB와 독립된 대용량 실험용 MySQL 및 Spring 접속 프로필을 제공한다.

**Architecture:** 기본 Compose와 `coupon` DB는 수정하지 않는다. 전용 Compose 파일이 MySQL 컨테이너, `3307` 포트, `coupon_large` DB, 독립 볼륨을 만들고, Spring `large-db` 프로필이 이 DB만 바라본다.

**Tech Stack:** Docker Compose, MySQL 8.0.36, Spring Boot, SQL

## Global Constraints

- 기존 `docker-compose.yml`, `scripts/db/`, `coupon` DB, `3306` 포트, `mysql-data` 볼륨은 변경하지 않는다.
- 대용량 DB는 컨테이너 `coupon-mysql-large`, 포트 `3307`, DB `coupon_large`, 볼륨 `mysql-large-data`를 사용한다.
- 데이터 적재 및 성능 개선용 인덱스는 이후 단계에서 다룬다.

---

### Task 1: 전용 MySQL과 초기 스키마 추가

**Files:**
- Create: `docker-compose.large-db.yml`
- Create: `scripts/large-db/schema.sql`

**Produces:** `docker compose -f docker-compose.large-db.yml up -d`로 기동되는 대용량 MySQL과 `member`, `coupon`, `coupon_issue` 테이블

- [ ] **Step 1: 실패하는 구성 검증 실행**

Run: `docker compose -f docker-compose.large-db.yml config`

Expected: 파일이 없으므로 실패.

- [ ] **Step 2: Compose 파일 작성**

`mysql-large` 서비스에 MySQL 8.0.36, `3307:3306`, `coupon_large`, 독립 볼륨, 전용 스키마 마운트를 정의한다.

- [ ] **Step 3: 전용 스키마 작성**

`member`의 PK, `coupon`의 PK, `coupon_issue`의 PK 및 `(coupon_id, member_id)` 유니크 제약을 만든다. `coupon_issue`에는 `status VARCHAR(20) NOT NULL`을 포함한다.

- [ ] **Step 4: 구성 검증 실행**

Run: `docker compose -f docker-compose.large-db.yml config`

Expected: exit 0 및 `3307:3306`, `mysql-large-data` 출력.

### Task 2: Spring 접속 프로필 추가

**Files:**
- Create: `src/main/resources/application-large-db.yaml`

**Produces:** `--spring.profiles.active=large-db`일 때 `localhost:3307/coupon_large`에 연결하는 datasource

- [ ] **Step 1: 프로필 파일 부재 확인**

Run: `Test-Path src/main/resources/application-large-db.yaml`

Expected: `False`.

- [ ] **Step 2: 프로필 파일 작성**

`spring.config.activate.on-profile: large-db`와 `LARGE_DB_*` 환경변수(기본값 `localhost`, `3307`, `coupon_large`)를 사용하는 datasource를 정의한다.

- [ ] **Step 3: 프로필 계약 검증**

Run: `Select-String -Path src/main/resources/application-large-db.yaml -Pattern '3307|coupon_large|large-db'`

Expected: 세 값이 모두 출력.

### Task 3: 기동·분리 검증 및 실행 문서화

**Files:**
- Modify: `README.md`

**Produces:** 대용량 DB 기동 및 Spring 프로필 실행 방법

- [ ] **Step 1: 전용 MySQL 기동**

Run: `docker compose -f docker-compose.large-db.yml up -d`

Expected: `coupon-mysql-large` 기동.

- [ ] **Step 2: 전용 스키마 검증**

Run: `docker compose -f docker-compose.large-db.yml exec -T mysql-large mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "SHOW TABLES"`

Expected: `member`, `coupon`, `coupon_issue` 출력.

- [ ] **Step 3: 기존 DB와 분리 검증**

Run: 기존 MySQL에서 `SELECT DATABASE()`와 전용 MySQL에서 `SELECT DATABASE()`를 실행한다.

Expected: 각각 `coupon`, `coupon_large`.

- [ ] **Step 4: README에 실행 명령 추가**

```text
docker compose -f docker-compose.large-db.yml up -d
./gradlew bootRun --args='--spring.profiles.active=large-db'
```

- [ ] **Step 5: 변경과 검증 결과를 커밋**

`git add`로 변경 파일만 스테이징하고 `feat: 대용량 실험용 MySQL 환경 분리` 메시지로 커밋한다.
