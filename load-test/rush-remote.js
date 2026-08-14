// EC2 측정용. k6 서버에서 앱 서버로 부하를 건다.
//
//   export TARGET=http://<앱서버-프라이빗IP>:8080
//   k6 run load-test/rush-remote.js
//
// 측정 조건은 전 조 통일 사항이다. 임의로 바꾸면 비교가 성립하지 않는다.
//   테스트 유저 20000명 (중복 없음) / ramp-up 60s
//
// rush.js(로컬 확인용, VU 2000·랜덤 회원)와는 다른 조건이므로 서로 비교하지 않는다.

import http from 'k6/http';
import { Counter } from 'k6/metrics';

const issued = new Counter('issued');
const soldOut = new Counter('sold_out');
const duplicated = new Counter('duplicated');
const errors = new Counter('errors');

// 회원 ID 는 VU 번호(__VU, 1부터)를 그대로 쓴다.
// Math.random() 으로 뽑으면 같은 회원이 겹쳐서 실행할 때마다 중복 건수가 달라지고,
// 조마다 다른 값이 나와 비교가 성립하지 않는다.
// VU 20000 = 서로 다른 회원 20000명.

// 미설정 시 localhost 로 조용히 흘러가면 전 요청이 실패한 채로 끝나므로
// 기본값을 두지 않고 즉시 중단시킨다.
const TARGET = __ENV.TARGET;
if (!TARGET) {
  throw new Error(
      'TARGET 이 없다'
  );
}

http.setResponseCallback(http.expectedStatuses(200, 409));

export const options = {
  scenarios: {
    rush: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '60s', target: 20000 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    errors: ['count==0'],
  },
};

export default function () {
  const memberId = __VU;

  const res = http.post(
      `${TARGET}/issue?couponId=1&memberId=${memberId}`
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
