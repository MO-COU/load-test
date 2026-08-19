#!/usr/bin/env bash
# 커넥션 풀(HikariCP) · Tomcat 워커 스레드 · InnoDB 버퍼 풀 사용량을
# 1초 간격으로 기록한다. k6 부하를 돌리기 직전에 별도 터미널에서 실행하고,
# 부하가 끝나면 Ctrl+C로 멈춘다.
#
#   bash scripts/large-db/collect-pool-metrics.sh <이름>
#
# 결과: docs/benchmark-results/sync-vs-async/raw/<이름>.tsv
#
# 사전 확인(최초 1회): 아래 grep으로 실제 지표 이름이 스크립트가 찾는
# 이름과 같은지 확인한다. Tomcat 지표는 스프링부트 버전에 따라
# tomcat_threads_busy_threads 처럼 뒤에 _threads가 붙을 수 있어
# prefix로만 찾는다.
#   curl -s localhost:8080/actuator/prometheus | grep -E 'hikaricp_connections|tomcat_threads'

set -euo pipefail

NAME="${1:?사용법: collect-pool-metrics.sh <이름>}"
BASE_URL="${BASE_URL:-http://localhost:8080}"
INTERVAL="${INTERVAL:-1}"
DB_CONTAINER="${DB_CONTAINER:-mysql-large}"
DB_USER="${DB_USER:-coupon_large}"
DB_PASSWORD="${DB_PASSWORD:-coupon-large-1234}"
DB_NAME="${DB_NAME:-coupon_large}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.large-db.yml}"

OUT_DIR="docs/benchmark-results/sync-vs-async/raw"
OUT_FILE="${OUT_DIR}/${NAME}.tsv"
mkdir -p "${OUT_DIR}"

INNODB_STATUS_SQL="SHOW GLOBAL STATUS WHERE Variable_name IN (
  'Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests',
  'Innodb_buffer_pool_pages_free','Innodb_buffer_pool_pages_total',
  'Innodb_os_log_fsyncs','Innodb_row_lock_waits');"

printf 'timestamp\thikari_active\thikari_pending\ttomcat_busy\ttomcat_max\tinnodb_buf_reads\tinnodb_buf_read_requests\tinnodb_buf_pages_free\tinnodb_buf_pages_total\tinnodb_os_log_fsyncs\tinnodb_row_lock_waits\n' \
  > "${OUT_FILE}"

echo "기록 시작 -> ${OUT_FILE} (Ctrl+C로 종료, ${INTERVAL}초 간격)"

while true; do
  metrics="$(curl -s "${BASE_URL}/actuator/prometheus" || true)"

  hikari_active=$(echo "$metrics" | grep '^hikaricp_connections_active' | awk '{print $NF}')
  hikari_pending=$(echo "$metrics" | grep '^hikaricp_connections_pending' | awk '{print $NF}')
  tomcat_busy=$(echo "$metrics" | grep '^tomcat_threads_busy' | awk '{print $NF}')
  tomcat_max=$(echo "$metrics" | grep '^tomcat_threads_config_max' | awk '{print $NF}')

  innodb="$(docker compose -f "${COMPOSE_FILE}" exec -T "${DB_CONTAINER}" \
    mysql -u"${DB_USER}" -p"${DB_PASSWORD}" -N -e "${INNODB_STATUS_SQL}" "${DB_NAME}" 2>/dev/null || true)"

  buf_reads=$(echo "$innodb" | awk '$1=="Innodb_buffer_pool_reads"{print $2}')
  buf_read_requests=$(echo "$innodb" | awk '$1=="Innodb_buffer_pool_read_requests"{print $2}')
  buf_pages_free=$(echo "$innodb" | awk '$1=="Innodb_buffer_pool_pages_free"{print $2}')
  buf_pages_total=$(echo "$innodb" | awk '$1=="Innodb_buffer_pool_pages_total"{print $2}')
  os_log_fsyncs=$(echo "$innodb" | awk '$1=="Innodb_os_log_fsyncs"{print $2}')
  row_lock_waits=$(echo "$innodb" | awk '$1=="Innodb_row_lock_waits"{print $2}')

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(date +%s)" \
    "${hikari_active:-NA}" "${hikari_pending:-NA}" \
    "${tomcat_busy:-NA}" "${tomcat_max:-NA}" \
    "${buf_reads:-NA}" "${buf_read_requests:-NA}" \
    "${buf_pages_free:-NA}" "${buf_pages_total:-NA}" \
    "${os_log_fsyncs:-NA}" "${row_lock_waits:-NA}" \
    | tee -a "${OUT_FILE}"

  sleep "${INTERVAL}"
done
