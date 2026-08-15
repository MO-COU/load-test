# 대용량 DB 성능 실험 결과

결과는 측정 조건을 기준으로 분리한다. 서로 다른 스키마·인덱스 조건의 결과를 같은 표에
섞지 않아 개선 전후를 명확히 비교하기 위함이다.

```text
benchmark-results/
├── baseline/                 # 성능 개선용 인덱스 미적용 기준선
│   ├── stage-1.md            # MEMBER 100,000 / COUPON_ISSUE 300,000
│   ├── stage-2.md            # MEMBER 300,000 / COUPON_ISSUE 900,000
│   ├── stage-3.md            # MEMBER 500,000 / COUPON_ISSUE 1,500,000
│   └── stage-4.md            # MEMBER 1,000,000 / COUPON_ISSUE 3,000,000
└── index-optimization/       # 인덱스 적용 후 재측정 결과를 기록할 위치
    └── stage-4-read.md       # Stage 4 회원별 조회 인덱스 가설 결과
```

`baseline`은 PK와 무결성 제약에 필요한 인덱스만 둔 상태의 결과다. 이후 인덱스를 적용한
결과는 `index-optimization` 아래에 별도 문서로 기록하고, 해당 문서에 적용한 인덱스와
비교 대상 Baseline 문서를 함께 명시한다.
