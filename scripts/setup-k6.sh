#!/usr/bin/env bash
# k6 서버 세팅. Ubuntu 24.04 LTS 기준.
# 이미 설치된 것은 건너뛰므로 여러 번 실행해도 안전하다.
#
#   sudo apt-get update && sudo apt-get install -y git \
#     && git clone https://github.com/MO-COU/load-test.git \
#     && bash load-test/scripts/setup-k6.sh 10.0.1.20
#
# 인자는 앱 서버의 프라이빗 IP.
set -euo pipefail

REPO_URL="https://github.com/MO-COU/load-test.git"
REPO="$HOME/load-test"
APP_IP="${1:-}"

echo "▶ [1/4] 파일 디스크립터 한도"
if grep -q "nofile 65535" /etc/security/limits.conf; then
	echo "   이미 설정됨 (현재 세션: $(ulimit -n))"
else
	sudo tee -a /etc/security/limits.conf >/dev/null <<'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
	echo "   설정함. 재접속해야 적용된다."
fi

echo "▶ [1.5/4] 임시 포트 범위"
# VU 20000 이면 한 대상 IP 로 동시 연결 2만 개를 연다.
# 기본 범위(32768-60999)는 약 2.8만 개뿐이라 TIME_WAIT 이 쌓이면 고갈된다.
if [ -f /etc/sysctl.d/99-k6.conf ]; then
	echo "   이미 설정됨 ($(cat /proc/sys/net/ipv4/ip_local_port_range))"
else
	echo 'net.ipv4.ip_local_port_range = 1024 65535' | sudo tee /etc/sysctl.d/99-k6.conf >/dev/null
	sudo sysctl -p /etc/sysctl.d/99-k6.conf
fi

echo "▶ [2/4] git, k6"
sudo apt-get update -qq
command -v git >/dev/null || sudo apt-get install -y git
if command -v k6 >/dev/null; then
	echo "   k6 이미 설치됨 ($(k6 version))"
else
	sudo apt-get install -y gnupg
	sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
		--keyserver hkp://keyserver.ubuntu.com:80 \
		--recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
	echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
		| sudo tee /etc/apt/sources.list.d/k6.list >/dev/null
	sudo apt-get update -qq
	sudo apt-get install -y k6
fi

echo "▶ [3/4] 저장소"
[ -d "$REPO/.git" ] || git clone "$REPO_URL" "$REPO"

echo "▶ [4/4] 실행 스크립트"
if [ -z "$APP_IP" ]; then
	echo "   앱 서버 IP 를 인자로 주지 않아 건너뛴다."
	echo "     bash load-test/scripts/setup-k6.sh 10.0.1.20"
else
	cat > "$HOME/k6.sh" <<SH
#!/usr/bin/env bash
# 부하 생성:  ~/k6.sh pessimistic 1
#
# 앱 서버가 바뀌면 아래 TARGET 만 고친다.
set -e
export TARGET=http://${APP_IP}:8080
SH
	cat >> "$HOME/k6.sh" <<'SH'

cd ~/load-test
mkdir -p ~/results
k6 run load-test/rush-remote.js 2>&1 | tee ~/results/$1-$2.txt
echo
echo "▶ 저장됨: ~/results/$1-$2.txt"
SH
	chmod +x "$HOME/k6.sh"
	echo "   ~/k6.sh 생성함 (TARGET=http://${APP_IP}:8080)"
fi

echo
echo "완료."
echo "재접속 후: ulimit -n  →  65535 확인 → ~/k6.sh <라벨> <회차>"