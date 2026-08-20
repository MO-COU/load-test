// 대용량 DB - 신규 발급 이력 저장(INSERT), 비동기 경로.
// large-db-insert.js(동기)와 정확히 같은 조건(VU, 반복 수, 쿠폰/회원 범위)으로
// 짝을 이뤄 비교하기 위한 스크립트. 계약만 다르다:
//   POST /benchmark/coupon-issues/async?couponId=4&memberId={memberId}   202
// 202는 "큐에 들어갔다"는 뜻이고 DB 반영은 별도 컨슈머가 나중에 한다.
// 실제로 몇 건이 반영됐는지는 큐가 다 빠진 뒤 verify-benchmark.sql로 확인한다.
//
//   docker compose -f docker-compose.large-db.yml exec -T mysql-large \
//     mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/prepare-benchmark.sql"
//   k6 run -e VUS=1|10|50 load-test/large-db-insert-async.js

import http from 'k6/http';
import exec from 'k6/execution';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const MEMBER_COUNT = Number(__ENV.MEMBER_COUNT || 100000);
const COUPON_ID = Number(__ENV.COUPON_ID || 4);

export const options = {
  scenarios: {
    insert_async: {
      executor: 'per-vu-iterations',
      vus: Number(__ENV.VUS || 1),
      iterations: Number(__ENV.ITERATIONS_PER_VU || 1000),
    },
  },
};

// API 계약: 큐 적재 성공(=DB 반영 아님) 시 202 ACCEPTED.
http.setResponseCallback(http.expectedStatuses(202));

export default function () {
  const memberId = (exec.scenario.iterationInTest % MEMBER_COUNT) + 1;
  http.post(
    `${BASE_URL}/benchmark/coupon-issues/async?couponId=${COUPON_ID}&memberId=${memberId}`,
      null,
      { tags: { name: 'benchmark_insert_async' } }
  );
}