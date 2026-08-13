# Baseline 쿠폰 발급

쿠폰 발급 동시성 제어 방식을 비교하기 위한 기준 구현입니다. 현재 단계는 Spring Boot, MySQL, JPA만 사용하며 의도적으로 동시성 제어를 하지 않습니다.

## 사전 조건

- JDK 21
- MySQL 8.x
- MySQL 명령줄 클라이언트(`mysql`)

Docker는 사용하지 않습니다.

## 처음 실행하기

### 1. 데이터베이스 생성

MySQL에 접속하여 한 번만 실행합니다.

```sql
CREATE DATABASE baseline
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

### 2. 로컬 접속 정보 파일 생성

운영체제에 맞는 명령으로 예시 파일을 복사한 뒤, `application-local.properties`의 값을 로컬 MySQL 환경에 맞게 수정합니다. 이 파일은 Git에 포함되지 않으며 한 번만 설정하면 됩니다.

#### Windows (PowerShell)

```powershell
Copy-Item .\src\main\resources\application-local.example.properties .\src\main\resources\application-local.properties
```

#### macOS / Linux (Bash, Zsh)

```bash
cp ./src/main/resources/application-local.example.properties ./src/main/resources/application-local.properties
```

파일 예시:

```properties
db.host=localhost
db.port=3306
db.name=baseline
db.username=root
db.password=비밀번호
```

### 3. 테이블과 샘플 데이터 초기화

운영체제에 맞는 명령 하나를 실행합니다.

#### Windows (PowerShell)

```powershell
.\scripts\db\initialize.ps1
```

#### macOS / Linux (Bash, Zsh)

```bash
bash ./scripts/db/initialize.sh
```

초기화 SQL은 `scripts/db/schema.sql`, `scripts/db/data.sql`에 있습니다. 두 스크립트는 SQL 파일을 순서대로 적용합니다.

### 4. 애플리케이션 실행

#### Windows (PowerShell)

```powershell
.\gradlew.bat bootRun
```

#### macOS / Linux (Bash, Zsh)

```bash
./gradlew bootRun
```

## API 확인

샘플 쿠폰과 회원을 초기화한 뒤 아래 요청으로 발급을 확인합니다.

```powershell
Invoke-RestMethod -Method Post `
  -Uri 'http://localhost:8080/api/coupons/1/issue' `
  -ContentType 'application/json' `
  -Body '{"memberId":1}'
```

재고가 있으면 HTTP 201로 발급 이력을 반환하고, 쿠폰 재고는 1 감소합니다. 재고가 없으면 HTTP 409를 반환합니다.

## GitHub에 올리기 전 로컬 확인

### 자동 테스트

운영체제에 맞는 명령 하나를 실행합니다. 이 테스트는 로컬 MySQL 없이 실행됩니다.

#### Windows (PowerShell)

```powershell
.\gradlew.bat test
```

#### macOS / Linux (Bash, Zsh)

```bash
./gradlew test
```

`BUILD SUCCESSFUL`이 출력되면 자동 테스트가 통과한 것입니다.

자동 테스트는 다음을 검증합니다.

- 쿠폰 재고가 1 감소하는지
- 정상 발급 시 CouponIssue 저장을 요청하는지
- 재고가 0이면 품절 예외가 발생하는지
- API가 HTTP 201과 발급 정보를 반환하는지

### MySQL 연동 확인

1. 위의 처음 실행하기 1~4단계를 완료한다.
2. 애플리케이션을 실행한 터미널은 그대로 둔다.
3. 다른 터미널에서 API 확인 명령을 한 번 실행한다.
4. 같은 요청을 다시 실행하면 응답의 `couponIssueId`가 달라지고 쿠폰 재고가 한 번 더 감소한다.

샘플 데이터는 회원 2,000명과 재고 1,000개인 `선착순 쿠폰` 1건입니다. 초기 상태로 되돌리려면 MySQL에서 `baseline` 데이터베이스를 삭제한 뒤 처음 실행하기 1~3단계를 다시 실행합니다.

## Baseline 원칙

발급은 회원 조회 → 쿠폰 조회 → 재고 확인 → 재고 차감 → 발급 이력 저장 순서로 실행합니다. 재고는 JPA Entity의 Dirty Checking으로만 변경합니다.

Redis, Kafka, 낙관적 락, 비관적 락, `SELECT FOR UPDATE`, Atomic UPDATE, 애플리케이션 락은 사용하지 않습니다. 따라서 동시 요청에서 발생할 수 있는 재고 정합성 문제는 이후 비교 구현에서 다룹니다.
