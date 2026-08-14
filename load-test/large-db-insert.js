// 대용량 DB - 신규 발급 이력 저장(INSERT) 부하.
// 계약: POST /benchmark/coupon-issues?couponId=4&memberId={memberId}
//
// UNIQUE(coupon_id, member_id) 충돌을 피하려고, 실행 전체에서 고유한 memberId를 만든다.
// 시드된 회원 범위(MEMBER_COUNT) 밖의 "신규 회원"으로 취급해 순수 INSERT 지연만 측정한다.
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
  vus: Number(__ENV.VUS || 1),
  duration: __ENV.DURATION || '30s',
};

// API 계약: 신규 발급 저장 성공 시 201 CREATED.
http.setResponseCallback(http.expectedStatuses(201));

export default function () {
  // iterationInTest는 실행 전체에서 0부터 증가하는 고유값 → memberId 충돌이 없다.
  const memberId = MEMBER_COUNT + exec.scenario.iterationInTest + 1;
  http.post(
    `${BASE_URL}/benchmark/coupon-issues?couponId=${COUPON_ID}&memberId=${memberId}`
  );
}