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

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const MEMBER_COUNT = Number(__ENV.MEMBER_COUNT || 100000);
// 시드 상태에서 status가 존재하는 쿠폰만 대상으로 한다.
const COUPON_IDS = [1, 2, 3];

export const options = {
  vus: Number(__ENV.VUS || 1),
  duration: __ENV.DURATION || '30s',
};

// API 계약: 204(ISSUED->USED 성공) / 404(이미 USED이거나 대상 없음).
// 둘 다 UPDATE 쿼리를 실제로 실행하므로(WHERE + 인덱스 조회) 정상 응답으로 취급한다.
// 시드가 50:50이라 랜덤 대상의 절반가량은 이미 USED → 404(무변경)로 나올 수 있다.
http.setResponseCallback(http.expectedStatuses(204, 404));

export default function () {
  const couponId = COUPON_IDS[Math.floor(Math.random() * COUPON_IDS.length)];
  const memberId = Math.floor(Math.random() * MEMBER_COUNT) + 1;
  http.patch(
    `${BASE_URL}/benchmark/coupon-issues/status?couponId=${couponId}&memberId=${memberId}`,
    null
  );
}