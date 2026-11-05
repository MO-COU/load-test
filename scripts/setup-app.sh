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

echo "▶ [1/6] 파일 디스크립터 한도"
if grep -q "nofile 65535" /etc/security/limits.conf; then
	echo "   이미 설정됨 (현재 세션: $(ulimit -n))"
else
	sudo tee -a /etc/security/limits.conf >/dev/null <<'EOF'
* soft nofile 65535
* hard nofile 65535
EOF
	echo "   설정함. 재접속해야 적용된다."
fi

echo "▶ [1.5/6] 커널 연결 큐"
# 2만 개 연결이 한꺼번에 도착한다. somaxconn 이 accept-count(32768)보다 작으면
# Tomcat 설정이 조용히 깎이므로 함께 올린다.
sudo sysctl -w net.core.somaxconn=32768 >/dev/null
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=32768 >/dev/null
echo 'net.core.somaxconn = 32768' | sudo tee /etc/sysctl.d/99-coupon.conf >/dev/null
echo 'net.ipv4.tcp_max_syn_backlog = 32768' | sudo tee -a /etc/sysctl.d/99-coupon.conf >/dev/null
echo "   somaxconn=$(cat /proc/sys/net/core/somaxconn) syn_backlog=$(cat /proc/sys/net/ipv4/tcp_max_syn_backlog)"

echo "▶ [2/6] git, curl, JDK 21"
sudo apt-get update -qq
command -v git >/dev/null || sudo apt-get install -y git
# metrics.sh 가 쓰므로 docker 설치 여부와 무관하게 확보한다.
command -v curl >/dev/null || sudo apt-get install -y curl
if command -v javac >/dev/null && javac -version 2>&1 | grep -q '^javac 21'; then
	echo "   JDK 21 이미 설치됨"
else
	sudo apt-get install -y openjdk-21-jdk
fi

echo "▶ [3/6] docker + compose"
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

echo "▶ [4/6] 저장소 + 실행 스크립트"
[ -d "$REPO/.git" ] || git clone "$REPO_URL" "$REPO"

# 저장소 안에 두면 git switch 때 사라지므로 홈에 만든다.
cat > "$HOME/app.sh" <<'SH'
#!/usr/bin/env bash
# 브랜치 전환 → 빌드 → 백그라운드 실행:  ~/app.sh exp/pessimistic-lock [커넥션 풀]
set -e
POOL=${2:-16}
cd ~/load-test
git switch "$1"
./gradlew -q clean bootJar
echo "▶ 브랜치 $(git branch --show-current) / 커밋 $(git rev-parse --short HEAD) / 커넥션 풀 $POOL"
~/stop.sh >/dev/null
ulimit -n 65535
# 통일 조건. exp/* 브랜치는 application.yaml 기본값이 이 값들로 바뀌기 전에 갈라져
# 기본값이 다르다(풀 50, accept-count 100, 관리 포트 없음). 환경변수로 같은 값을 넣는다.
# 커넥션 풀은 풀 크기 비교 때만 두 번째 인자로 바꾼다.
export DB_POOL_SIZE=$POOL TOMCAT_ACCEPT_COUNT=32768 TOMCAT_MAX_CONNECTIONS=30000 MANAGEMENT_SERVER_PORT=19090
nohup java -jar build/libs/*.jar > ~/app.log 2>&1 &
echo "▶ pid $! · 로그 ~/app.log"
for i in $(seq 1 90); do
	if curl -sf localhost:19090/actuator/health >/dev/null; then
		echo "▶ 기동 완료 (${i}초)"
		exit 0
	fi
	sleep 1
done
echo "▶ 90초 안에 기동하지 않았다. ~/app.log 를 확인한다"
exit 1
SH

cat > "$HOME/stop.sh" <<'SH'
#!/usr/bin/env bash
# 앱 중지:  ~/stop.sh
pkill -f 'java -jar build/libs' || true
sleep 3
echo "▶ 앱 중지"
SH

cat > "$HOME/reset.sh" <<'SH'
#!/usr/bin/env bash
# 성능 측정 직전 초기화:  ~/reset.sh          DB 재고만
#                          ~/reset.sh redis    Redis 재고까지 (lua / watch)
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
# 자원 사용률 수집:  ~/metrics.sh <결과파일이름>   (before.sh 가 띄우고 after.sh 가 죽인다)
mkdir -p ~/results
OUT=~/results/metrics-${1:-result}.txt
: > "$OUT"

while true; do
	# 0.2초 간격: 빠른 방식은 8초에 끝나 1초로는 포화 구간 표본이 부족하다.
	m=$(curl -s --max-time 1 localhost:19090/actuator/prometheus \
		| grep -E '^(hikaricp_connections_active|hikaricp_connections_pending|hikaricp_connections_max|tomcat_threads_busy|tomcat_threads_current)' \
		| awk '{printf "%s=%s ", $1, $2}')
	[ -n "$m" ] && echo "$(date +%s.%N) $m" >> "$OUT"
	sleep 0.2
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

cat > "$HOME/drain.sh" <<'SH'
#!/usr/bin/env bash
# 부하 종료 후 판정 전에 실행. k6 가 타임아웃으로 포기해도 서버는 계속 처리하므로,
# 발급 행 수가 멈출 때까지 기다린 뒤 세야 실제 발급 수가 나온다.
cd ~/load-test
Q() { sudo docker exec coupon-mysql mysql -N -B -ucoupon -pcoupon1234 coupon -e "$1" 2>/dev/null; }
PREV=-1; STABLE=0
for i in $(seq 1 36); do
	N=$(Q "SELECT COUNT(*) FROM coupon_issue WHERE coupon_id=1")
	[ "$N" = "$PREV" ] && STABLE=$((STABLE+1)) || STABLE=0
	PREV=$N
	[ "$STABLE" -ge 2 ] && { echo "▶ 배수 완료: 발급 $N"; exit 0; }
	sleep 5
done
echo "▶ 배수 타임아웃: 발급 $PREV"
SH

cat > "$HOME/netstat.sh" <<'SH'
#!/usr/bin/env bash
# 커널이 버린 연결 수:  ~/netstat.sh
# ListenOverflows = accept 큐 넘침 · ListenDrops = 그 외
awk '/^TcpExt:/{
  if(!h){for(i=2;i<=NF;i++)k[i]=$i; h=1; next}
  for(i=2;i<=NF;i++) if(k[i]=="ListenOverflows"||k[i]=="ListenDrops") printf "%s=%s ", k[i], $i
  print ""
}' /proc/net/netstat
SH

cat > "$HOME/before.sh" <<'SH'
#!/usr/bin/env bash
# 부하 직전:  ~/before.sh <이름> [redis]   초기화 + 사전 지표 + 모니터 기동
set -e
N=$1
mkdir -p ~/results
exec > >(tee ~/results/before-$N.txt) 2>&1
~/reset.sh ${2:-} >/dev/null 2>&1
echo "=== dbstat BEFORE ==="; ~/dbstat.sh 2>/dev/null | grep -v Warning
echo "=== netstat BEFORE ==="; ~/netstat.sh
pkill -f metrics.sh 2>/dev/null || true
pkill -x vmstat 2>/dev/null || true
pkill -f "sport = :8080" 2>/dev/null || true
nohup ~/metrics.sh "$N" >/dev/null 2>&1 &
# 시각(-t)을 함께 찍어 부하 구간만 잘라 볼 수 있게 한다.
nohup vmstat -t 1 > ~/results/vmstat-$N.txt 2>&1 &
# accept 큐에 쌓인 연결 수(Recv-Q)
nohup bash -c 'while true; do ss -ltn "sport = :8080" | awk "NR>1{print \$2}"; sleep 0.2; done' > ~/results/qdepth-$N.txt 2>&1 &
echo "▶ 모니터 기동: metrics · vmstat · qdepth"
SH

cat > "$HOME/after.sh" <<'SH'
#!/usr/bin/env bash
# 배수 완료 후:  ~/after.sh <이름>   모니터 중지 + 사후 지표 + 판정
set -e
N=$1
exec > >(tee ~/results/after-$N.txt) 2>&1
pkill -f metrics.sh 2>/dev/null || true
pkill -x vmstat 2>/dev/null || true
pkill -f "sport = :8080" 2>/dev/null || true
sleep 1
echo "=== dbstat AFTER ==="; ~/dbstat.sh 2>/dev/null | grep -v Warning
echo "=== netstat AFTER ==="; ~/netstat.sh
echo "=== verify ==="; ~/verify.sh 2>/dev/null | grep -v Warning
echo "=== metrics 최대값 ==="
# 지표 이름에 = 가 들어 있어 줄 끝의 =숫자 만 값으로 본다.
awk '{for(i=2;i<=NF;i++){t=$i; if(match(t,/=[0-9.]+$/)){k=substr(t,1,RSTART-1); v=substr(t,RSTART+1)+0; sub(/[{].*/,"",k); if(v>m[k])m[k]=v}}}
     END{for(k in m) printf "  %-32s %s\n", k, m[k]}' ~/results/metrics-$N.txt | sort
echo "=== CPU/RAM ==="
# free 는 캐시를 뺀 값이라 낮게 보인다. 부족 판단은 swap 으로 한다.
# 평균은 부하 전후의 유휴 구간까지 포함한다. 부하가 몰린 순간은 id 최저로 본다.
awk 'NR>2 && $13+0==$13 {n++; us+=$13; sy+=$14; id+=$15; wa+=$16; if($15<mi||n==1)mi=$15; if($4<mf||n==1)mf=$4; si+=$7; so+=$8}
     END{if(n)printf "  CPU 평균 us=%.1f%% sy=%.1f%% id=%.1f%% wa=%.1f%% · id 최저 %d%% · free 최저 %.1fGB · swap %d/%d\n", us/n, sy/n, id/n, wa/n, mi, mf/1048576, si, so}' ~/results/vmstat-$N.txt
echo "=== accept 큐 최대 깊이 ==="
sort -n ~/results/qdepth-$N.txt | tail -1
SH

chmod +x "$HOME"/app.sh "$HOME"/stop.sh "$HOME"/reset.sh "$HOME"/verify.sh \
	"$HOME"/metrics.sh "$HOME"/dbstat.sh "$HOME"/netstat.sh \
	"$HOME"/before.sh "$HOME"/drain.sh "$HOME"/after.sh
echo "   ~/app.sh ~/before.sh ~/drain.sh ~/after.sh ~/stop.sh 생성함"

echo "▶ [5/6] MySQL / Redis"
cd "$REPO"
sudo docker compose up -d
sudo docker compose ps

echo
echo "완료. mysql, redis 가 healthy 인지 위에서 확인하라."
echo "재접속 후: ulimit -n  →  65535 확인 → ~/app.sh <브랜치>"
