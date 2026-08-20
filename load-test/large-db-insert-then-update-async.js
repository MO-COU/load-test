// 대용량 DB - INSERT 직후 같은 건을 UPDATE(ISSUED -> USED)하는 혼합 부하, 비동기 경로.
// large-db-insert-then-update.js(동기)와 정확히 같은 조건으로 짝을 이룬다.
//
// 계약:
//   POST  /benchmark/coupon-issues/async?couponId=4&memberId={memberId}          202
//   PATCH /benchmark/coupon-issues/status/async?couponId=4&memberId={memberId}   202
//
//   docker compose -f docker-compose.large-db.yml exec -T mysql-large \
//     mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/prepare-benchmark.sql"
//   k6 run -e VUS=1|10|50 load-test/large-db-insert-then-update-async.js

import http from 'k6/http';
import exec from 'k6/execution';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const MEMBER_COUNT = Number(__ENV.MEMBER_COUNT || 100000);
const COUPON_ID = Number(__ENV.COUPON_ID || 4);

export const options = {
  scenarios: {
    insert_then_update_async: {
      executor: 'per-vu-iterations',
      vus: Number(__ENV.VUS || 1),
      iterations: Number(__ENV.ITERATIONS_PER_VU || 1000),
    },
  },
};

export default function () {
  const memberId = (exec.scenario.iterationInTest % MEMBER_COUNT) + 1;

  http.post(
    `${BASE_URL}/benchmark/coupon-issues/async?couponId=${COUPON_ID}&memberId=${memberId}`,
    null,
    {
      tags: { name: 'benchmark_insert_then_update_async_insert' },
      responseCallback: http.expectedStatuses(202),
    }
  );

  http.patch(
    `${BASE_URL}/benchmark/coupon-issues/status/async?couponId=${COUPON_ID}&memberId=${memberId}`,
    null,
    {
      tags: { name: 'benchmark_insert_then_update_async_update' },
      responseCallback: http.expectedStatuses(202),
    }
  );
}