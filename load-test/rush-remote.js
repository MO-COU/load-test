// EC2 측정용. k6 서버에서 앱 서버로 부하를 건다.
//
//   1단계 — 한계점 찾기 (계단식으로 올리며 자원이 고갈되는 VU 를 찾는다)
//     PROFILE=step ~/k6.sh pessimistic step
//
//   2단계 — 6개 브랜치 비교 (1단계에서 찾은 VU 로 고정)
//     VUS=4000 ~/k6.sh pessimistic 1
//
// 이 파일은 성능만 잰다. 정확성(재고 초과·중복 발급)은 로컬 rush.js 담당이다.
// 재고를 안 마르게 두고(~/reset.sh) 회원을 매번 새로 만들어,
// 모든 요청이 똑같이 "진짜 발급" 이 되도록 조건을 맞춘다.
//
// 측정 조건은 전 브랜치 통일 사항이다. 임의로 바꾸면 비교가 성립하지 않는다.

import http from 'k6/http';
import { Counter } from 'k6/metrics';

const issued = new Counter('issued');
const soldOut = new Counter('sold_out');
const duplicated = new Counter('duplicated');
const errors = new Counter('errors');

// 미설정 시 localhost 로 조용히 흘러가면 전 요청이 실패한 채로 끝나므로
// 기본값을 두지 않고 즉시 중단시킨다.
const TARGET = __ENV.TARGET;
if (!TARGET) {
  throw new Error('TARGET 이 없다');
}

const VUS = Number(__ENV.VUS || 20000);

// 계단식: 각 단계마다 올린 뒤 30초 유지한다.
// 유지 구간이 없으면 지표가 안정되기 전에 다음 단계로 넘어가서
// "VU 2000 일 때 커넥션 풀이 어땠나" 를 읽을 수 없다.
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

// 램프업 뒤에 반드시 유지 구간을 둔다.
// 램프업만 하면 목표 VU 에 마지막 순간 딱 한 번 닿고 끝나서,
// TPS 와 p95 가 "0~VUS 구간의 평균" 이 된다. VUS 에서의 값이 아니다.
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
    // 넘어도 측정은 계속한다. redis-watch 는 재시도 한도 초과 시
    // 의도적으로 5xx 를 내므로 0 이 아닌 것이 정상일 수 있다.
    errors: [{ threshold: 'count==0', abortOnFail: false }],
  },
};

export default function () {
  // 요청마다 서로 다른 회원을 쓴다. __VU(VU 번호)와 __ITER(그 VU 의 반복 횟수)를
  // 조합하면 절대 겹치지 않는다.
  //
  // 같은 회원이 다시 오면 "이미 발급됨" 으로 일찍 끝나 DB 쓰기가 없다.
  // 그 싼 요청의 비율은 브랜치가 빠를수록 커지므로, 그대로 두면
  // 빠른 브랜치일수록 처리량이 부풀려진다.
  const memberId = __VU * 1000000 + __ITER + 1;

  const res = http.post(
      `${TARGET}/issue?couponId=1&memberId=${memberId}`,
      null,
      // URL 에 memberId 가 들어가면 k6 가 URL 마다 메트릭을 따로 만든다.
      // 회원 2만 명이면 시계열이 20만 개가 되어 k6 자체가 병목이 되므로
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
