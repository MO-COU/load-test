// 로컬 정합성 확인용. 성능 수치는 이 파일로 재지 않는다.
// k6·앱·MySQL·Redis 가 한 대에서 CPU 를 나눠 쓰므로 처리량이 왜곡된다.
//
// 실행 전 초기화
//   docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/reset.sql"
//   docker compose exec -T redis redis-cli FLUSHALL
//   docker compose exec -T redis redis-cli SET coupon:stock:1 1000   # Redis 브랜치만
//
// 실행 후 판정
//   docker compose exec -T mysql mysql -ucoupon -pcoupon1234 coupon -e "source /scripts/verify.sql"
//   docker compose exec -T redis redis-cli GET coupon:stock:1        # Redis 브랜치만

import http from 'k6/http';
import { Counter } from 'k6/metrics';

const issued = new Counter('issued');
const soldOut = new Counter('sold_out');
const duplicated = new Counter('duplicated');
const errors = new Counter('errors');

// 재고보다 많아야 품절이 나고, VU 수와 같아야 회원이 겹쳐
// 같은 회원의 동시 요청(중복 발급 경합)이 만들어진다.
const MEMBER_POOL = 2000;

http.setResponseCallback(http.expectedStatuses(200, 409));

export const options = {
  scenarios: {
    rush: {
      // 램프업을 쓰면 재고가 저부하 구간에서 말라 경합이 안 일어난다.
      // 전원이 동시에 한 번씩 요청해 재고 경계를 최대 경합에서 지나게 한다.
      executor: 'per-vu-iterations',
      vus: MEMBER_POOL,
      iterations: 1,
      maxDuration: '60s',
    },
  },
  thresholds: {
    errors: ['count==0'],
  },
};

export default function () {
  const memberId = Math.floor(Math.random() * MEMBER_POOL) + 1;

  const res = http.post(
      `http://localhost:8080/issue?couponId=1&memberId=${memberId}`,
      null,
      // 태그가 없으면 k6 가 URL 마다 메트릭을 따로 만들어 스스로 병목이 된다.
      { tags: { name: 'issue' } }
  );

  if (res.status === 200) {
    issued.add(1);
  } else if (res.status === 409) {
    if (res.body && res.body.includes('DUPLICATED')) {
      duplicated.add(1);
    } else {
      soldOut.add(1);
    }
  } else {
    errors.add(1);
  }
}