# 적응형 알람 — 시스템 코어 & 시뮬레이터

습관화 과학에 근거한 적응형 알람 앱의 **핵심 시스템**과, 그것을 폰 없이
검증하는 **Python 시뮬레이터**. 설계 근거는 동봉된 설계 보고서를 따른다.

## 구조

```
core/   ★ 계약(contract). 순수 로직. Python↔Dart 동일하게 구현하는 단일 기준점.
  config.py    튜닝 가능한 모든 하이퍼파라미터(Params) 한곳 집결
  models.py    AlarmSegment / AlarmRecord / SoundProfile
  events.py    원시 울림·스누즈·해제 이벤트 → AlarmRecord (+검증)
  scoring.py   활성 상호작용 시간 → 가산 결합 점수 → 교란 보정
  trend.py     시간감쇠 EWMA, 음원별 기준선(모집단 수축), 관리 상한선
  decision.py  다중 조건 교체 판정 + 다음 음원 선택
  engine.py    ★ AlarmEngine: 상태 보관·제안·수락/거절·JSON 직렬화 (앱이 미러링)

sim/    Python 전용. 합성 데이터로 core/ 를 검증. 앱에는 들어가지 않는다.
  generate.py  합성 사용자 + 습관화 곡선 + 잡음(수면단계·수면부채·요일)
  run.py       실제 AlarmEngine을 구동하는 하니스 + 집계 지표
  tune.py      파라미터 스윕(탐지율 vs 오탐률)

examples/
  engine_usage.py  엔진 사용 전체 흐름(원시이벤트→제안→저장/복원→수락). Dart 포팅 참조

tests/
  test_core.py     17개 단위 + 골든(parity) 테스트
```

앱(Flutter/Dart)은 OS 알람 스케줄링·이벤트 기록·저장·UI를 맡고, `core/` 로직을
Dart로 **그대로 포팅**한다. `engine.py`의 흐름과 `to_dict()` JSON 형태가 그 경계다.
네트워크·서버 없이 동작해야 하므로 핵심 판정은 전부 온디바이스에서 이뤄진다.

## 실행

```bash
python3 -m sim.run            # 단일 사용자 트레이스 + 300명 집계 지표
python3 -m sim.tune           # 파라미터 스윕(탐지율 vs 오탐률 표)
python3 -m examples.engine_usage   # 엔진 API 전체 흐름 데모
python3 -m unittest -v        # 테스트(17개)
```

## 현재 기본값 성능 (sim.run, 300명×90일)

| 지표 | 값 |
|---|---|
| 탐지율(습관화 잡아냄) | 91% |
| 오탐자 비율(헛 제안 받은 비습관화 사용자) | 15.3% |
| 첫 교체까지 평균(탐지 지연) | 28.7일 |

`core/config.py`의 `lambda_·L·consecutive_above`를 `sim/tune.py`로 스윕해 정했다.

## 튜닝 손잡이 (core/config.py)

| 상수 | 의미 |
|---|---|
| `lambda_` | EWMA 민감도(클수록 잡음에 민감) |
| `L` | 관리 상한선 폭(클수록 둔감, 오탐↓) |
| `baseline_days` | 기준선 수집 일수(탐지 지연과 직결) |
| `consecutive_above` | 교체 전 연속 초과 일수 |
| `snooze_weight` | 스누즈가 점수에 더하는 가중치 |
| `min_days_between_swaps` | 교체 사이 최소 간격 |
| `proposal_snooze_days` | 거절 후 다시 제안 안 하는 기간 |

## 알려진 한계(설계 보고서 대응)

- **수면 단계 교란**: 시뮬레이터의 `sigma_stage`가 습관화 신호에 맞먹는 잡음을
  넣는다. 대조 그룹 오탐률이 이 누수를 직접 보여준다.(보고서 2.6, 3장)
- **기준선 ≫ 습관화 주기**: 기준선 14일이 탐지 지연(~29일)으로 그대로 나타난다.
  더 줄이려면 잠정 기준선을 모집단 값으로 일찍 확정하는 설계 변경이 필요(오탐과 맞바꿈).
- **효과 "검증" 아님**: 교체 후 점수 하락은 탈습관화일 수도, 새 음원이 더 잘
  깨우는 소리일 수도 있어 인과로 단정하지 않는다.(보고서 2.6)
