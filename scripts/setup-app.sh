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

echo "▶ [2/5] git, JDK 21"
sudo apt-get update -qq
command -v git >/dev/null || sudo apt-get install -y git
if command -v javac >/dev/null && javac -version 2>&1 | grep -q '^javac 21'; then
	echo "   JDK 21 이미 설치됨"
else
	sudo apt-get install -y openjdk-21-jdk
fi

echo "▶ [3/5] docker + compose"
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
	echo "   이미 설치됨"
else
	sudo apt-get install -y ca-certificates curl
	sudo install -m 0755 -d /etc/apt/keyrings
	sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
	sudo chmod a+r /etc/apt/keyrings/docker.asc
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
		| sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
	sudo apt-get update -qq
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
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
# 측정 직전 초기화:  ~/reset.sh          DB 재고만
#                    ~/reset.sh redis    Redis 재고까지 (lua / watch 브랜치용)
#
# 재고를 바꾸려면 아래 STOCK 만 고친다.
# 저장소의 data.sql 은 로컬용(1000)이라 건드리지 않는다.
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
# 측정 직후 결과 확인:  ~/verify.sh
cd ~/load-test
sudo docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"
echo -n "redis coupon:stock:1 = "
sudo docker compose exec -T redis redis-cli GET coupon:stock:1
SH

chmod +x "$HOME"/app.sh "$HOME"/reset.sh "$HOME"/verify.sh
echo "   ~/app.sh  ~/reset.sh  ~/verify.sh 생성함"

echo "▶ [5/5] MySQL / Redis"
cd "$REPO"
sudo docker compose up -d
sudo docker compose ps

echo
echo "완료. mysql, redis 가 healthy 인지 위에서 확인하라."
echo "재접속 후: ulimit -n  →  65535 확인 → ~/app.sh <브랜치>"
