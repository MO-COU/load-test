import http from 'k6/http';
import exec from 'k6/execution';
import { Counter } from 'k6/metrics';

const issued = new Counter('issued');
const soldOut = new Counter('sold_out');
const duplicated = new Counter('duplicated');
const errors = new Counter('errors');

// 재고 소진과 중복 발급의 409는 정상 동작이다.
// 이걸 빼면 http_req_failed가 50% 넘게 찍혀서 결과를 읽을 수 없다.
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
    // 판정 기준: 5xx 0건
    errors: ['count==0'],
  },
};

export default function () {
  // VU 하나가 하나의 회원. 같은 VU의 2회차 이후 요청은 전부 중복 발급 시도가 된다.
  const memberId = exec.vu.idInTest;

  const res = http.post(
    `http://localhost:8080/issue?couponId=1&memberId=${memberId}`
  );

  if (res.status === 200) {
    issued.add(1);
  } else if (res.status === 409) {
    // 재고 소진과 중복 발급을 응답 본문으로 구분한다.
    // 서버가 SOLD_OUT / DUPLICATED 를 본문에 실어 보내야 한다.
    if (res.body && res.body.includes('DUPLICATED')) {
      duplicated.add(1);
    } else {
      soldOut.add(1);
    }
  } else {
    // 5xx뿐 아니라 400, 404 같은 예상 밖 응답도 여기서 잡는다.
    // else if (status >= 500) 으로 두면 그 외 상태코드가 조용히 사라진다.
    errors.add(1);
  }
}
