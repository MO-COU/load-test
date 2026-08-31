// EC2 성능 측정용 — 동시 몰림 시나리오. 정합성은 CouponIssueConcurrencyTest 담당이다.
//
//   ~/k6.sh <결과파일이름> spike
//
// 회원 20,000명이 재고 10,000장을 두고 동시에 신청한다.
// 1인 1요청이라 방식과 무관하게 부하량이 20,000건으로 고정된다.
// (rush-remote.js 는 램프업 60초 조건을 지킨 지속 부하 측정이다. 둘은 다른 것을 잰다.)

import http from 'k6/http';
import { Counter, Trend } from 'k6/metrics';

const issued = new Counter('issued');
const soldOut = new Counter('sold_out');
const duplicated = new Counter('duplicated');
const errors = new Counter('errors');
// 발급 시각(테스트 시작 기준 ms). max 가 완판 시간, med 가 절반 소진 시점이다.
const issueElapsed = new Trend('issue_elapsed');

const TARGET = __ENV.TARGET;
if (!TARGET) {
  throw new Error('TARGET 이 없다');
}

const VUS = Number(__ENV.VUS || 20000);

http.setResponseCallback(http.expectedStatuses(200, 409));

export const options = {
  scenarios: {
    spike: {
      // VU 를 미리 만들어두고 한꺼번에 출발시킨다. 램프업이 없어야 전원이
      // 재고가 남은 상태에서 경쟁한다.
      executor: 'per-vu-iterations',
      vus: VUS,
      iterations: 1,
      maxDuration: '300s',   // 느린 방식(pessimistic 369 req/s)도 끝낼 수 있게
    },
  },
};

export function setup() {
  return { t0: Date.now() };
}

export default function (data) {
  // VU 번호 = 회원 번호. 중복 회원이 없어야 전원이 실제 경쟁자가 된다.
  // 재요청하지 않는다 — 요청 수를 20,000 으로 고정해야 방식 간 부하가 같아진다.
  const memberId = __VU;

  const res = http.post(
      `${TARGET}/issue?couponId=1&memberId=${memberId}`,
      null,
      // 태그가 없으면 k6 가 URL 마다 메트릭을 만들어 스스로 병목이 된다. 지우지 말 것.
      { tags: { name: 'issue' } }
  );

  if (res.status === 200) {
    issued.add(1);
    issueElapsed.add(Date.now() - data.t0);
  } else if (res.status === 409) {
    if (res.body && res.body.includes('DUPLICATED')) {
      duplicated.add(1);
    } else {
      soldOut.add(1);
    }
  } else {
    // 5xx 또는 타임아웃. 사용자는 끝내 결과를 받지 못했다.
    errors.add(1);
  }
}
