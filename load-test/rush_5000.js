import http from 'k6/http';
import { Counter } from 'k6/metrics';

const issued = new Counter('issued');
const soldOut = new Counter('sold_out');
const duplicated = new Counter('duplicated');
const errors = new Counter('errors');

const MEMBER_POOL = 5000;

http.setResponseCallback(http.expectedStatuses(200, 409));

export const options = {
  scenarios: {
    rush: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '60s', target: 5000 },
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
    `http://localhost:8080/issue?couponId=1&memberId=${memberId}`
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
