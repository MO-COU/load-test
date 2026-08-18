#!/usr/bin/env bash
# 앱 서버 세팅. Ubuntu 24.04 LTS 기준.
# 이미 설치된 것은 건너뛰므로 여러 번 실행해도 안전하다.
#
#   sudo apt-get update && sudo apt-get install -y git \
#     && git clone https://github.com/MO-COU/load-test.git \
#     && bash load-test/scripts/setup-app.sh
#
# docker 는 sudo 로 쓴다. docker 그룹에 넣으면 재접속 단계만 늘어난다.
set -euo pipefail

REPO_URL="https://github.com/MO-COU/load-test.git"
REPO="$HOME/load-test"

echo "▶ [1/5] 파일 디스크립터 한도"
if grep -q "nofile 65535" /etc/security/limits.conf; then
	echo "   이미 설정됨 (현재 세션: $(ulimit -n))"
else
	sudo tee -a /etc/security/limits.conf >/dev/null <<'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
	echo "   설정함. 재접속해야 적용된다."
fi

echo "▶ [2/5] git, curl, JDK 21"
sudo apt-get update -qq
command -v git >/dev/null || sudo apt-get install -y git
# metrics.sh 가 쓰므로 docker 설치 여부와 무관하게 확보한다.
command -v curl >/dev/null || sudo apt-get install -y curl
if command -v javac >/dev/null && javac -version 2>&1 | grep -q '^javac 21'; then
	echo "   JDK 21 이미 설치됨"
else
	sudo apt-get install -y openjdk-21-jdk
fi

echo "▶ [3/5] docker + compose"
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
	echo "   이미 설치됨"
else
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
		| sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
	sudo apt-get update -qq
	# docker-ce 가 docker-ce-cli, containerd.io 를 의존성으로 끌어온다.
	sudo apt-get install -y docker-ce docker-compose-plugin
fi

echo "▶ [4/5] 저장소 + 실행 스크립트"
[ -d "$REPO/.git" ] || git clone "$REPO_URL" "$REPO"

# 저장소 안에 두면 git switch 때 사라지므로 홈에 만든다.
cat > "$HOME/app.sh" <<'SH'
#!/usr/bin/env bash
# 브랜치 전환 후 앱 실행:  ~/app.sh exp/pessimistic-lock
set -e
cd ~/load-test
git switch "$1"
./gradlew clean bootJar
echo
echo "▶ 브랜치 $(git branch --show-current) / 커밋 $(git rev-parse --short HEAD)"
echo
java -jar build/libs/*.jar
SH

cat > "$HOME/reset.sh" <<'SH'
#!/usr/bin/env bash
# 성능 측정 직전 초기화:  ~/reset.sh          DB 재고만
#                          ~/reset.sh redis    Redis 재고까지 (lua / watch / redisson)
#
set -e
STOCK=10000

cd ~/load-test
sudo docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon \
	-e "source /scripts/reset.sql; UPDATE coupon SET total_quantity=$STOCK WHERE coupon_id=1;"
sudo docker compose exec -T redis redis-cli FLUSHALL

if [ "${1:-}" = "redis" ]; then
	sudo docker compose exec -T redis redis-cli SET coupon:stock:1 $STOCK
fi

echo "▶ 초기화 완료 (재고 $STOCK)"
SH

cat > "$HOME/verify.sh" <<'SH'
#!/usr/bin/env bash
# 측정 직후 정확성 판정:  ~/verify.sh
set -e
cd ~/load-test

# docker exec 직접 호출: compose exec 는 명령 치환 안에서 stdin 때문에 안 끝날 수 있다.
Q() { sudo docker exec coupon-mysql mysql -N -B -ucoupon -pcoupon1234 coupon -e "$1" 2>/dev/null; }

sudo docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"

# 재고 누수 검사 (redis-lua, redis-watch)
STOCK=$(sudo docker exec coupon-redis redis-cli GET coupon:stock:1 | tr -d '\r')
if [ -z "$STOCK" ]; then
	echo "재고누수  SKIP  (Redis 재고 키 없음 = DB 전용 브랜치)"
else
	ROWS=$(Q "SELECT COUNT(*) FROM coupon_issue WHERE coupon_id=1")
	TOTAL=$(Q "SELECT total_quantity FROM coupon WHERE coupon_id=1")
	if [ "$((ROWS + STOCK))" = "$TOTAL" ]; then
		echo "재고누수  PASS  (발급 $ROWS + 남은재고 $STOCK = $TOTAL)"
	else
		echo "재고누수  FAIL  (발급 $ROWS + 남은재고 $STOCK != 초기재고 $TOTAL)"
	fi
fi
SH

cat > "$HOME/metrics.sh" <<'SH'
#!/usr/bin/env bash
# 자원 사용률 수집:  ~/metrics.sh <결과파일이름>
# k6 시작 직전에 실행하고 끝나면 Ctrl+C.
mkdir -p ~/results
OUT=~/results/metrics-${1:-result}.txt

echo "▶ 수집 시작 → $OUT   (Ctrl+C 로 중단)"
while true; do
	m=$(curl -s localhost:8080/actuator/prometheus \
		| grep -E '^(hikaricp_connections_active|hikaricp_connections_pending|hikaricp_connections_max|tomcat_threads_busy|tomcat_threads_current)' \
		| awk '{printf "%s=%s ", $1, $2}')
	echo "$(date +%s) $m" >> "$OUT"
	sleep 1
done
SH

cat > "$HOME/dbstat.sh" <<'SH'
#!/usr/bin/env bash
# MySQL 락 통계:  ~/dbstat.sh   측정 전후로 찍어 차이를 본다.
cd ~/load-test
sudo docker compose exec -T mysql mysql -uroot -proot1234 -e "
SHOW GLOBAL STATUS WHERE Variable_name IN (
  'Innodb_row_lock_waits','Innodb_row_lock_time_avg','Innodb_row_lock_current_waits',
  'Com_insert','Com_update','Com_rollback');"
SH

chmod +x "$HOME"/app.sh "$HOME"/reset.sh "$HOME"/verify.sh "$HOME"/metrics.sh "$HOME"/dbstat.sh
echo "   ~/app.sh  ~/reset.sh  ~/verify.sh  ~/metrics.sh  ~/dbstat.sh 생성함"

echo "▶ [5/5] MySQL / Redis"
cd "$REPO"
sudo docker compose up -d
sudo docker compose ps

echo
echo "완료. mysql, redis 가 healthy 인지 위에서 확인하라."
echo "재접속 후: ulimit -n  →  65535 확인 → ~/app.sh <브랜치>"
