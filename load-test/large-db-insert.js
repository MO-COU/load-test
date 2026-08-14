// 대용량 DB - 신규 발급 이력 저장(INSERT) 부하.
// 계약: POST /benchmark/coupon-issues?couponId=4&memberId={memberId}
//
// 쿠폰 4는 측정 전 비어 있으므로, 시드된 회원 범위 안에서 고유한 memberId를 사용한다.
// 반복 실행 전에는 prepare-benchmark.sql로 쿠폰 4를 비운다.
//
//   docker compose -f docker-compose.large-db.yml exec -T mysql-large \
//     mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/prepare-benchmark.sql"
//   k6 run -e VUS=1|10|50 load-test/large-db-insert.js

import http from 'k6/http';
import exec from 'k6/execution';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const MEMBER_COUNT = Number(__ENV.MEMBER_COUNT || 100000);
const COUPON_ID = Number(__ENV.COUPON_ID || 4);

export const options = {
  scenarios: {
    insert: {
      executor: 'per-vu-iterations',
      vus: Number(__ENV.VUS || 1),
      iterations: Number(__ENV.ITERATIONS_PER_VU || 1000),
    },
  },
};

// API 계약: 신규 발급 저장 성공 시 201 CREATED.
http.setResponseCallback(http.expectedStatuses(201));

export default function () {
  const memberId = (exec.scenario.iterationInTest % MEMBER_COUNT) + 1;
  http.post(
    `${BASE_URL}/benchmark/coupon-issues?couponId=${COUPON_ID}&memberId=${memberId}`,
      null,
      { tags: { name: 'benchmark_insert' } }
  );
}
