// 대용량 DB - 상태 변경(UPDATE, ISSUED -> USED) 부하.
// 계약: PATCH /benchmark/coupon-issues/status?couponId={couponId}&memberId={memberId}
//
// status가 있는 쿠폰 1~3을 대상으로 랜덤 회원의 이력을 바꾼다.
// 반복 실행 전에는 prepare-benchmark.sql로 쿠폰 1~3 상태를 시드(50:50)로 복구한다.
//
//   docker compose -f docker-compose.large-db.yml exec -T mysql-large \
//     mysql -ucoupon_large -pcoupon-large-1234 coupon_large -e "source /scripts/large-db/prepare-benchmark.sql"
//   k6 run -e VUS=1|10|50 load-test/large-db-update.js

import http from 'k6/http';
import exec from 'k6/execution';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const MEMBER_COUNT = Number(__ENV.MEMBER_COUNT || 100000);
const ISSUED_PER_COUPON = MEMBER_COUNT / 2;
const COUPON_IDS = [1, 2, 3];

export const options = {
  scenarios: {
    update: {
      executor: 'per-vu-iterations',
      vus: Number(__ENV.VUS || 1),
      iterations: Number(__ENV.ITERATIONS_PER_VU || 1000),
    },
  },
};

// 모든 요청이 실제 ISSUED -> USED 변경이 되도록, 시드 규칙의 ISSUED 조합만 사용한다.
http.setResponseCallback(http.expectedStatuses(204));

export default function () {
  const index = exec.scenario.iterationInTest;
  const couponId = COUPON_IDS[
    Math.floor(index / ISSUED_PER_COUPON) % COUPON_IDS.length
  ];
  const memberOffset = index % ISSUED_PER_COUPON;
  const memberId = couponId % 2 === 1
    ? (memberOffset + 1) * 2
    : memberOffset * 2 + 1;

  http.patch(
    `${BASE_URL}/benchmark/coupon-issues/status?couponId=${couponId}&memberId=${memberId}`,
      null,
      { tags: { name: 'benchmark_update' } }
  );
}
