// EC2 성능 측정용. 정합성은 CouponIssueConcurrencyTest 담당이다.
//
//   ~/k6.sh <결과파일이름>
//
// 측정 조건은 전 조 통일 사항이다. 임의로 바꾸면 비교가 성립하지 않는다.
//   테스트 유저 20000명 (중복 없음) / ramp-up 60s

import http from 'k6/http';
import { Counter } from 'k6/metrics';

const issued = new Counter('issued');
const soldOut = new Counter('sold_out');
const duplicated = new Counter('duplicated');
const errors = new Counter('errors');

const TARGET = __ENV.TARGET;
if (!TARGET) {
  throw new Error('TARGET 이 없다');
}

const VUS = Number(__ENV.VUS || 20000);

http.setResponseCallback(http.expectedStatuses(200, 409));

export const options = {
  scenarios: {
    rush: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '60s', target: VUS },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    // redis-watch 는 재시도 소진 시 5xx 를 내므로 0 이 아닐 수 있다.
    errors: [{ threshold: 'count==0', abortOnFail: false }],
  },
};

export default function () {
  // VU 수 = 회원 수. 랜덤은 회차마다 중복 건수가 달라져 쓰지 않는다.
  const memberId = __VU;

  const res = http.post(
      `${TARGET}/issue?couponId=1&memberId=${memberId}`,
      null,
      // 태그가 없으면 k6 가 URL 마다 메트릭을 만들어 스스로 병목이 된다. 지우지 말 것.
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
