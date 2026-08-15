// 로컬 정확성 확인용. 성능 수치는 이 파일로 재지 않는다.
// k6·앱·MySQL·Redis 가 한 대에서 CPU 를 나눠 쓰므로 처리량이 왜곡된다.
//
// 회원을 랜덤으로 뽑아 같은 회원의 요청이 동시에 겹치게 만든다.
// EC2 측정용 rush-remote.js 는 회원이 매번 달라 이 겹침이 없다.
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

const MEMBER_POOL = 2000;

http.setResponseCallback(http.expectedStatuses(200, 409));

export const options = {
  scenarios: {
    rush: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '60s', target: 2000 },
      ],
      gracefulRampDown: '30s',
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
      // URL 에 memberId 가 들어가면 k6 가 URL 마다 메트릭을 따로 만든다.
      // 회원 2000명이면 시계열이 2000배가 되어 k6 자체가 병목이 되므로
      // 이름을 하나로 고정한다.
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