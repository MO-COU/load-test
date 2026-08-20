#!/usr/bin/env bash
# 비동기 경로용 VU 스윕. run-vu-sweep.sh와 조건(VU, 총 요청량, 초기화
# 절차)은 동일하게 맞추고, 차이는 두 가지뿐이다:
#   - 대상 스크립트가 large-db-insert-async.js / large-db-insert-then-update-async.js
#   - k6가 끝난 뒤 큐가 다 빠질 때까지 기다렸다가(drain) 검증한다
#     (비동기라 202 응답 시점 != DB 반영 시점이라서)
#
# 실행 전에 앱을 원하는 BATCH_SIZE로 이미 띄워둬야 한다(환경변수는
# 기동 시점에만 읽히므로). 1단계(배치 없음): BENCHMARK_BATCH_SIZE=1,
# 2단계(배치): BENCHMARK_BATCH_SIZE=100(기본값).
#
#   bash scripts/large-db/run-vu-sweep-async.sh <stage-label> [vu1 vu2 ...]
#
# 예: bash scripts/large-db/run-vu-sweep-async.sh stage0-async-nobatch 10 50 100 200 300 400 500

set -uo pipefail

STAGE="${1:?사용법: run-vu-sweep-async.sh <stage-label> [vu1 vu2 ...]}"
shift
VU_LIST=("$@")
if [ ${#VU_LIST[@]} -eq 0 ]; then
  VU_LIST=(10 50 100 200 300 400 500)
fi

TOTAL_REQUESTS=10000
BASE_URL="http://localhost:8080"
COMPOSE_FILE="docker-compose.large-db.yml"
DB_CONTAINER="mysql-large"
DB_USER="coupon_large"
DB_PASSWORD="coupon-large-1234"
DB_NAME="coupon_large"
DRAIN_TIMEOUT_SEC=60

OUT_DIR="docs/benchmark-results/sync-vs-async/raw"
OUT_FILE="${OUT_DIR}/${STAGE}.tsv"
LOG_DIR="${OUT_DIR}/${STAGE}-k6-logs"
mkdir -p "${OUT_DIR}" "${LOG_DIR}"

INNODB_SQL="SHOW GLOBAL STATUS WHERE Variable_name IN ('Innodb_buffer_pool_reads','Innodb_buffer_pool_read_requests','Innodb_buffer_pool_pages_free','Innodb_buffer_pool_pages_total','Innodb_os_log_fsyncs','Innodb_row_lock_waits');"

OLD_SUMMARY_ROWS=()

if [ -f "${OUT_FILE}" ]; then
  TAB="$(printf '\t')"
  while IFS= read -r line; do
    OLD_SUMMARY_ROWS+=("${line#\# }")
  done < <(grep -E "^# (insert-only|insert-update)${TAB}" "${OUT_FILE}" || true)

  awk '/^# ===== Summary/{exit} {print}' "${OUT_FILE}" | sed -e '${/^$/d}' > "${OUT_FILE}.tmp"
  mv "${OUT_FILE}.tmp" "${OUT_FILE}"

  for vus in "${VU_LIST[@]}"; do
    for workload in insert-only insert-update; do
      awk -F'\t' -v w="$workload" -v v="$vus" '!($1==w && $2==v)' "${OUT_FILE}" > "${OUT_FILE}.tmp"
      mv "${OUT_FILE}.tmp" "${OUT_FILE}"

      FILTERED=()
      for row in "${OLD_SUMMARY_ROWS[@]}"; do
        rw="${row%%$'\t'*}"
        rest="${row#*$'\t'}"
        rv="${rest%%$'\t'*}"
        if [ "$rw" == "$workload" ] && [ "$rv" == "$vus" ]; then
          continue
        fi
        FILTERED+=("$row")
      done
      OLD_SUMMARY_ROWS=("${FILTERED[@]}")
    done
  done
else
  printf 'workload\tvus\titerations_per_vu\ttotal_requests\telapsed_in_run_sec\thikari_active\thikari_pending\ttomcat_busy\ttomcat_max\tinnodb_buf_reads\tinnodb_buf_read_requests\tinnodb_buf_pages_free\tinnodb_buf_pages_total\tinnodb_os_log_fsyncs\tinnodb_row_lock_waits\tqueue_size\n' \
    > "${OUT_FILE}"
fi

reset_coupon4() {
  docker compose -f "${COMPOSE_FILE}" exec -T "${DB_CONTAINER}" \
    mysql -u"${DB_USER}" -p"${DB_PASSWORD}" "${DB_NAME}" \
    -e "source /scripts/large-db/prepare-benchmark.sql" >/dev/null 2>&1
}

innodb_snapshot() {
  docker compose -f "${COMPOSE_FILE}" exec -T "${DB_CONTAINER}" \
    mysql -u"${DB_USER}" -p"${DB_PASSWORD}" -N -e "${INNODB_SQL}" "${DB_NAME}" 2>/dev/null
}

get_field() {
  echo "$1" | awk -v k="$2" '$1==k{print $2}'
}

queue_size() {
  curl -s "${BASE_URL}/benchmark/coupon-issues/queue-size" 2>/dev/null || echo "NA"
}

collect_loop() {
  local workload="$1" vus="$2" iters="$3" total="$4" run_start="$5"
  while true; do
    metrics="$(curl -s "${BASE_URL}/actuator/prometheus" || true)"
    hikari_active=$(echo "$metrics" | grep '^hikaricp_connections_active' | awk '{print $NF}')
    hikari_pending=$(echo "$metrics" | grep '^hikaricp_connections_pending' | awk '{print $NF}')
    tomcat_busy=$(echo "$metrics" | grep '^tomcat_threads_busy' | awk '{print $NF}')
    tomcat_max=$(echo "$metrics" | grep '^tomcat_threads_config_max' | awk '{print $NF}')

    innodb="$(innodb_snapshot)"
    buf_reads=$(get_field "$innodb" "Innodb_buffer_pool_reads")
    buf_read_requests=$(get_field "$innodb" "Innodb_buffer_pool_read_requests")
    buf_pages_free=$(get_field "$innodb" "Innodb_buffer_pool_pages_free")
    buf_pages_total=$(get_field "$innodb" "Innodb_buffer_pool_pages_total")
    os_log_fsyncs=$(get_field "$innodb" "Innodb_os_log_fsyncs")
    row_lock_waits=$(get_field "$innodb" "Innodb_row_lock_waits")
    qsize=$(queue_size)

    now=$(date +%s)
    elapsed=$((now - run_start))

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$workload" "$vus" "$iters" "$total" "$elapsed" \
      "${hikari_active:-NA}" "${hikari_pending:-NA}" \
      "${tomcat_busy:-NA}" "${tomcat_max:-NA}" \
      "${buf_reads:-NA}" "${buf_read_requests:-NA}" \
      "${buf_pages_free:-NA}" "${buf_pages_total:-NA}" \
      "${os_log_fsyncs:-NA}" "${row_lock_waits:-NA}" "${qsize:-NA}" \
      >> "${OUT_FILE}"

    sleep 1
  done
}

SUMMARY_ROWS=()

wait_for_drain() {
  local waited=0
  while [ "$(queue_size)" != "0" ] && [ "$waited" -lt "$DRAIN_TIMEOUT_SEC" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  echo "$waited"
}

run_one() {
  local workload="$1" script="$2" vus="$3"
  local iters=$(( (TOTAL_REQUESTS + vus - 1) / vus ))
  local total=$(( iters * vus ))

  echo "== ${workload} vus=${vus} iterations_per_vu=${iters} total=${total} =="

  reset_coupon4

  local before_innodb; before_innodb="$(innodb_snapshot)"
  local before_fsync; before_fsync=$(get_field "$before_innodb" "Innodb_os_log_fsyncs")
  local before_reads; before_reads=$(get_field "$before_innodb" "Innodb_buffer_pool_reads")
  local before_read_req; before_read_req=$(get_field "$before_innodb" "Innodb_buffer_pool_read_requests")

  local run_start; run_start=$(date +%s)
  collect_loop "$workload" "$vus" "$iters" "$total" "$run_start" &
  local collector_pid=$!

  local k6_log="${LOG_DIR}/${workload}-vu${vus}.log"
  k6 run -e VUS="${vus}" -e ITERATIONS_PER_VU="${iters}" "load-test/${script}" > "${k6_log}" 2>&1
  local k6_exit=$?

  local k6_end; k6_end=$(date +%s)
  local elapsed=$((k6_end - run_start))

  local drain_sec; drain_sec=$(wait_for_drain)

  local run_end; run_end=$(date +%s)
  local total_elapsed=$((run_end - run_start))

  kill "${collector_pid}" 2>/dev/null
  wait "${collector_pid}" 2>/dev/null

  local after_innodb; after_innodb="$(innodb_snapshot)"
  local after_fsync; after_fsync=$(get_field "$after_innodb" "Innodb_os_log_fsyncs")
  local after_reads; after_reads=$(get_field "$after_innodb" "Innodb_buffer_pool_reads")
  local after_read_req; after_read_req=$(get_field "$after_innodb" "Innodb_buffer_pool_read_requests")

  local max_active max_pending max_busy max_rowlock max_qsize
  max_active=$(awk -F'\t' -v w="$workload" -v v="$vus" '$1==w && $2==v {print $6}' "${OUT_FILE}" | sort -n | tail -1)
  max_pending=$(awk -F'\t' -v w="$workload" -v v="$vus" '$1==w && $2==v {print $7}' "${OUT_FILE}" | sort -n | tail -1)
  max_busy=$(awk -F'\t' -v w="$workload" -v v="$vus" '$1==w && $2==v {print $8}' "${OUT_FILE}" | sort -n | tail -1)
  max_rowlock=$(awk -F'\t' -v w="$workload" -v v="$vus" '$1==w && $2==v {print $15}' "${OUT_FILE}" | sort -n | tail -1)
  max_qsize=$(awk -F'\t' -v w="$workload" -v v="$vus" '$1==w && $2==v {print $16}' "${OUT_FILE}" | sort -n | tail -1)

  local k6_avg k6_p95 k6_failed k6_throughput
  k6_avg=$(grep -E 'http_req_duration\.+:' "${k6_log}" | head -1 | grep -oE 'avg=[^ ]+' | cut -d= -f2)
  k6_p95=$(grep -E 'http_req_duration\.+:' "${k6_log}" | head -1 | grep -oE 'p\(95\)=[^ ]+' | cut -d= -f2)
  k6_failed=$(grep -E 'http_req_failed\.+:' "${k6_log}" | head -1 | grep -oE '^[[:space:]]*http_req_failed\.+: [0-9.]+%' | grep -oE '[0-9.]+%')
  k6_throughput=$(grep -E 'iterations\.+:' "${k6_log}" | head -1 | grep -oE '[0-9.]+/s')

  SUMMARY_ROWS+=("$(printf '%s\t%s\t%s\t%s\t%ss\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tdrain=%ss,max_queue=%s\t%s(exit=%s)' \
    "$workload" "$vus" "$iters" "$total" "$elapsed" \
    "${max_active:-NA}" "${max_pending:-NA}" "${max_busy:-NA}" "${max_rowlock:-NA}" \
    "$((after_fsync - before_fsync))" "$((after_reads - before_reads))" "$((after_read_req - before_read_req))" \
    "$drain_sec" "${max_qsize:-NA}" \
    "avg=${k6_avg:-NA} p95=${k6_p95:-NA} fail=${k6_failed:-NA} thr=${k6_throughput:-NA}" "$k6_exit")")

  echo "   -> k6_elapsed=${elapsed}s drain=${drain_sec}s max_queue=${max_qsize:-NA} max_active=${max_active:-NA} max_pending=${max_pending:-NA} k6_exit=${k6_exit}"
}

for vus in "${VU_LIST[@]}"; do
  run_one "insert-only" "large-db-insert-async.js" "$vus"
done

for vus in "${VU_LIST[@]}"; do
  run_one "insert-update" "large-db-insert-then-update-async.js" "$vus"
done

{
  echo ""
  echo "# ===== Summary (Stage: ${STAGE}) ====="
  echo "# workload  vus  iterations_per_vu  total_requests  k6_elapsed  max_hikari_active  max_hikari_pending  max_tomcat_busy  max_row_lock_waits  fsync_delta  buf_reads_delta  buf_read_requests_delta  drain_and_max_queue  k6_summary"
  {
    for row in "${OLD_SUMMARY_ROWS[@]}"; do echo "$row"; done
    for row in "${SUMMARY_ROWS[@]}"; do echo "$row"; done
  } | sort -t "$(printf '\t')" -k1,1 -k2,2n | sed 's/^/# /'
} >> "${OUT_FILE}"

echo "완료 -> ${OUT_FILE}"
