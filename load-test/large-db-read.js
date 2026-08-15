// 대용량 DB - 회원별 쿠폰 조회 부하.
// 계약: GET /benchmark/members/{memberId}/coupon-issues
//
// 실행 조건은 환경변수로 통일한다(1 / 10 / 50 VU 동일 조건):
//   k6 run -e VUS=1  load-test/large-db-read.js
//   k6 run -e VUS=10 load-test/large-db-read.js
//   k6 run -e VUS=50 load-test/large-db-read.js
// 결과: k6 요약의 http_req_duration(avg, p95)과 http_req_failed(오류율)로 확인한다.

import http from 'k6/http';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const MEMBER_COUNT = Number(__ENV.MEMBER_COUNT || 100000);

export const options = {
  vus: Number(__ENV.VUS || 1),
  duration: __ENV.DURATION || '30s',
};

http.setResponseCallback(http.expectedStatuses(200));

export default function () {
  const memberId = Math.floor(Math.random() * MEMBER_COUNT) + 1;
  http.get(
    `${BASE_URL}/benchmark/members/${memberId}/coupon-issues`,
    { tags: { name: 'benchmark_read' } }
  );
}
