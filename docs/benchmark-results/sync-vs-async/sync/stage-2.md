# Stage 2 측정 결과 (동기 적재)

배경 데이터: `coupon_issue` 900,000건(`seed-stage.sql`, `@member_count=300000`).
방법은 [`stage-0.md`](stage-0.md)와 동일. 원본은 [`../raw/stage2.tsv`](../raw/stage2.tsv).

| VU | 워크로드 | Avg | p95 | 실패율 | max hikari_pending | max tomcat_busy | row_lock_waits(누적) |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | INSERT만 | 8.14ms | 11.24ms | 0% | 0 | 11 | 55 |
| 50 | INSERT만 | 19.16ms | 27.72ms | 0% | 0 | 51 | 55 |
| 100 | INSERT만 | 34.2ms | 50.37ms | 0% | 0* | 1* | 55 |
| 200 | INSERT만 | 69.87ms | 120.06ms | 0% | 0* | 1* | 55 |
| 300 | INSERT만 | 102.55ms | 216.38ms | 0.43% | 0* | 1* | 55 |
| 400 | INSERT만 | 125.17ms | 225.29ms | 1.55% | 0* | 1* | 55 |
| 500 | INSERT만 | 161.35ms | 280.48ms | 2.50% | 0* | 1* | 55 |
| 10 | INSERT+UPDATE | 7.88ms | 10.55ms | 0% | 0 | 11 | 55 |
| 50 | INSERT+UPDATE | 17.08ms | 24.02ms | 0% | 0 | 51 | 55 |
| 100 | INSERT+UPDATE | 39.8ms | 63.13ms | 0% | 50 | 101 | 55 |
| 200 | INSERT+UPDATE | 81.63ms | 151.62ms | 0.86% | **149** | **200** | 55 |
| 300 | INSERT+UPDATE | 110.59ms | 230.49ms | 0.76% | **149** | **200** | 59 |
| 400 | INSERT+UPDATE | 144.36ms | 271.8ms | 2.25% | **149** | **200** | 67 |
| 500 | INSERT+UPDATE | 166.89ms | 281.74ms | 2.65% | **149** | **200** | 79 |

`*` 폴링이 짧은 부하 구간을 놓친 줄. `row_lock_waits`는 Stage 1 끝(55)에서
이어지는 누적 카운터.

## 관찰

- INSERT만은 이 단계에서 lock wait가 전혀 새로 생기지 않았다(55 고정) —
  INSERT는 여전히 서로 다른 행이라 경합이 없다는 걸 재확인.
- INSERT+UPDATE는 VU=300부터 lock wait가 계속 늘고(59→67→79), VU당 증가폭도
  Stage 1(6,8,5)보다 커졌다(4,8,12) — 배경 데이터가 커질수록 UPDATE의 행
  탐색·잠금 비용이 조금씩 늘고 있음을 시사.
- INSERT+UPDATE의 VU=500 실패율이 2.65%로 Stage 1(12.80%)보다 낮게
  나왔다 — Stage 1↔2 사이 순서가 안 맞는 것도 노이즈 범위. 정확한
  실패율 숫자보다 "VU 200대 포화, 300대부터 실패 시작"이라는 패턴을
  본다.
