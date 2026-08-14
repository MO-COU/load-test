// 대용량 DB - 쿠폰별·상태별 발급 건수 집계 부하.
// 계약: GET /benchmark/coupon-issues/summary
//
//   k6 run -e VUS=1|10|50 load-test/large-db-summary.js
// 결과: k6 요약의 http_req_duration(avg, p95)과 http_req_failed(오류율)로 확인한다.

import http from 'k6/http';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
  vus: Number(__ENV.VUS || 1),
  duration: __ENV.DURATION || '30s',
};

http.setResponseCallback(http.expectedStatuses(200));

export default function () {
  http.get(`${BASE_URL}/benchmark/coupon-issues/summary`);
}