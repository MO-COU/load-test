# Stage 1 측정 결과 (동기 적재)

배경 데이터: `coupon_issue` 300,000건(`seed-stage.sql`, `@member_count=100000`).
방법은 [`stage-0.md`](stage-0.md)와 동일. 원본은 [`../raw/stage1.tsv`](../raw/stage1.tsv).

| VU | 워크로드 | Avg | p95 | 실패율 | max hikari_pending | max tomcat_busy | row_lock_waits(누적) |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 | INSERT만 | 8.23ms | 10.99ms | 0% | 0 | 11 | 38 |
| 50 | INSERT만 | 19.6ms | 28.45ms | 0% | 0 | 1* | 38 |
| 100 | INSERT만 | 47.76ms | 73.77ms | 0% | 50 | 101 | 38 |
| 200 | INSERT만 | 82.47ms | 133.16ms | 0% | **149** | **200** | 38 |
| 300 | INSERT만 | 108.94ms | 238ms | 1.82% | 0* | 1* | 44 |
| 400 | INSERT만 | 132.28ms | 252.01ms | 0.44% | 0* | 1* | 50 |
| 500 | INSERT만 | 150.82ms | 274.32ms | 6.77% | 0* | 1* | 55 |
| 10 | INSERT+UPDATE | 7.81ms | 10.37ms | 0% | 0 | 11 | 38 |
| 50 | INSERT+UPDATE | 21.09ms | 31.98ms | 0% | 0 | 51 | 38 |
| 100 | INSERT+UPDATE | 44.8ms | 75.08ms | 0% | 50 | 101 | 38 |
| 200 | INSERT+UPDATE | 76.48ms | 130.43ms | 0% | **149** | **200** | 38 |
| 300 | INSERT+UPDATE | 97.62ms | 189.92ms | 1.21% | **149** | **200** | 44 |
| 400 | INSERT+UPDATE | 149.96ms | 280.2ms | 1.52% | **149** | **200** | 50 |
| 500 | INSERT+UPDATE | 196.42ms | 488.6ms | 12.80% | **149** | **200** | 55 |

`*` 폴링이 짧은 부하 구간을 놓친 줄. `row_lock_waits`는 MySQL 시작 이후
누적 카운터라 절대값이 아니라 **직전 줄과의 차이**로 읽는다 — Stage 0
끝(38)에서 시작해 VU=300부터 INSERT만·INSERT+UPDATE 모두에서 새 lock
wait가 생기기 시작한다.

## 관찰

- VU=200에서 포화(풀 100% 소진), VU=300~500에서 실패 시작 — Stage 0와
  같은 큰 그림. 데이터가 30만 건으로 늘어도 breakpoint 위치 자체는 아직
  크게 안 바뀜.
- INSERT+UPDATE의 실패율이 VU=500에서 12.80%로 Stage 0(24.11%)보다
  낮게 나왔다 — 단조 악화가 아니라 로컬 측정 노이즈 범위로 본다
  (자세한 노이즈 논의는 `sync/stage-0.md` 참고).
- `row_lock_waits`가 VU=300부터 처음으로 새로 발생 — Stage 0(VU=500부터)보다
  더 낮은 VU에서 나타나기 시작했다. 배경 데이터가 늘면서 인덱스 구조
  변경 시 실제 잠금 경합이 더 쉽게 발생하는 것으로 보인다.
