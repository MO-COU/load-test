// EC2 측정용. 성능만 잰다. 정합성은 로컬 rush.js 담당이다.
//
//   계단식   PROFILE=step ~/k6.sh <결과파일이름>
//   고정     VUS=20000    ~/k6.sh <결과파일이름>
//
// 측정 조건은 전 브랜치 통일 사항이다. 임의로 바꾸면 비교가 성립하지 않는다.

import http from 'k6/http';
import { Counter } from 'k6/metrics';

const issued = new Counter('issued');
const soldOut = new Counter('sold_out');
const duplicated = new Counter('duplicated');
const errors = new Counter('errors');

// 기본값을 두면 오설정 시 전 요청이 실패한 채로 끝나므로 즉시 중단시킨다.
const TARGET = __ENV.TARGET;
if (!TARGET) {
  throw new Error('TARGET 이 없다');
}

const VUS = Number(__ENV.VUS || 20000);

// 유지 구간이 없으면 지표가 안정되기 전에 다음 단계로 넘어간다.
const STEP_STAGES = [
  { duration: '10s', target: 1000 },
  { duration: '30s', target: 1000 },
  { duration: '10s', target: 2000 },
  { duration: '30s', target: 2000 },
  { duration: '10s', target: 4000 },
  { duration: '30s', target: 4000 },
  { duration: '10s', target: 8000 },
  { duration: '30s', target: 8000 },
];

// 램프업만 하면 목표 VU 에 마지막 순간 한 번 닿고 끝나 전 구간 평균이 된다.
const FIXED_STAGES = [
  { duration: '20s', target: VUS },
  { duration: '60s', target: VUS },
];

const stages = __ENV.PROFILE === 'step' ? STEP_STAGES : FIXED_STAGES;

http.setResponseCallback(http.expectedStatuses(200, 409));

export const options = {
  scenarios: {
    rush: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: stages,
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    // redis-watch 는 재시도 소진 시 의도적으로 5xx 를 내므로 0 이 아닐 수 있다.
    errors: [{ threshold: 'count==0', abortOnFail: false }],
  },
};

export default function () {
  // VU 수 = 회원 수. 2회차부터는 중복 요청이 되며, 그 중복을 어디서
  // 쳐내는지가 비교 대상이다. 랜덤은 회차마다 값이 달라져 쓰지 않는다.
  const memberId = __VU;

  const res = http.post(
      `${TARGET}/issue?couponId=1&memberId=${memberId}`,
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
