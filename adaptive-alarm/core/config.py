"""튜닝 가능한 모든 하이퍼파라미터를 한곳에 모은다.

이렇게 모아두면 (1) 시뮬레이터에서 여러 설정을 한 번에 비교(스윕)할 수 있고,
(2) Dart 포팅 때 설정 클래스 하나로 그대로 옮길 수 있다. core/ 의 함수들은
이 Params 를 받아 동작하며, 인자를 생략하면 DEFAULT 를 쓴다.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Params:
    # --- 점수(scoring) ---
    snooze_weight: float = 0.35       # 스누즈 한 번이 점수에 더하는 가중치
    sleep_debt_coef: float = 0.08     # 수면 부채 1시간당 보정량
    workday_coef: float = 0.10        # 근무일 고정 보정량
    phone_dist_coef: float = 0.40     # 휴대폰 거리 1.0일 때 보정량
    target_sleep_hours: float = 7.5   # 이보다 적게 잔 만큼을 수면 부채로 봄
    extreme_debt_hours: float = 3.0   # 이 이상 부족하면 판정에서 제외

    # --- 추세(trend) ---
    # λ·L·consecutive_above 는 sim/tune.py 스윕으로 정함:
    # 기본값(0.25/2.7/3)은 오탐자 35%로 시끄러웠고, 아래 설정이 탐지율 90%+를
    # 지키면서 오탐자를 ~15%로 절반 줄인다.(탐지 지연 ~29일은 baseline_days에 기인)
    lambda_: float = 0.20             # EWMA 평활 계수(클수록 잡음에 민감)
    L: float = 3.3                    # 관리 상한선 폭 계수(클수록 둔감, 오탐↓)
    baseline_days: int = 14           # 기준선 수집 일수(탐지 지연과 직결)
    shrinkage_k: int = 7              # 모집단 기준선 수축 강도(가상 관측 수)

    # --- 판정(decision) ---
    consecutive_above: int = 4        # 교체 전 연속으로 기준선 초과해야 할 일수
    min_days_between_swaps: int = 14  # 교체 사이 최소 간격


DEFAULT = Params()
