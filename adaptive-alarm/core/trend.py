"""추세 추적: 시간감쇠 EWMA, 음원별 기준선, 관리 상한선. (보고서 2.3)

상태(TrendState)는 한 사용자 × 한 음원 조합마다 따로 관리한다. 음원이 바뀌면
새 음원에 대해 기준선을 처음부터 다시 모은다. 음원마다 깨우는 힘이 본질적으로
다르므로 한 음원의 기준선을 다른 음원에 물려쓸 수 없기 때문이다.(보고서 1.2, 2.4)
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

# EWMA 평활 계수. 최근 값에 두는 비중. 0.2~0.3 권장, 0.25 기본.(보고서 2.3)
LAMBDA = 0.25

# 관리 상한선 계수 L. 엄밀한 UCL = baseline_mean + L·σ·√(λ/(2-λ)).(보고서 2.3 각주)
L = 2.7

# 기준선 확정에 필요한 최소 관측 일수. 7개로는 표준편차가 불안정하므로 14로 늘림.
BASELINE_DAYS = 14

# 모집단 기준선으로부터의 수축 강도(가상 관측 수). 개인 데이터가 이만큼 쌓이면
# 모집단 절반·개인 절반이 된다. 개인 값이 쌓일수록 모집단 영향은 줄어든다.
SHRINKAGE_K = 7


@dataclass
class TrendState:
    """한 사용자 × 한 음원 조합의 추세 상태."""

    ewma: float | None = None             # 현재 EWMA 값
    last_day_index: int | None = None     # 마지막으로 갱신한 일자(달력 간격 계산용)
    baseline_scores: list[float] = field(default_factory=list)  # 기준선 수집용 버퍼
    baseline_mean: float | None = None    # 확정된 기준선 평균
    baseline_sigma: float | None = None   # 확정된 기준선 표준편차
    recent_above: list[bool] = field(default_factory=list)  # 최근 며칠 기준선 초과 여부

    @property
    def baseline_ready(self) -> bool:
        return self.baseline_mean is not None


def _ewma_alpha_for_gap(gap_days: int) -> float:
    """달력 간격을 반영한 유효 평활 계수.

    표준 EWMA는 간격을 무시하지만, 며칠을 비우면 과거 추세의 신뢰도가 떨어지므로
    비운 날수만큼 과거 비중을 줄인다. gap=1이면 LAMBDA, 간격이 커질수록 1에 수렴해
    현재 값을 더 믿는다.(보고서 2.3)
    """
    gap = max(1, gap_days)
    return 1.0 - (1.0 - LAMBDA) ** gap


def update(state: TrendState, day_index: int, mean_for_population: float,
           sigma_for_population: float, score: float) -> TrendState:
    """하루치 보정 점수를 받아 추세 상태를 갱신한다.

    mean/sigma_for_population: 개인 데이터가 부족한 초기에 빌려오는 모집단 값.
    """
    # 1) 시간감쇠 EWMA 갱신
    if state.ewma is None:
        state.ewma = score
    else:
        gap = day_index - (state.last_day_index if state.last_day_index is not None else day_index)
        alpha = _ewma_alpha_for_gap(gap)
        state.ewma = alpha * score + (1.0 - alpha) * state.ewma
    state.last_day_index = day_index

    # 2) 기준선 수집/확정
    if not state.baseline_ready:
        state.baseline_scores.append(score)
        if len(state.baseline_scores) >= BASELINE_DAYS:
            _finalize_baseline(state, mean_for_population, sigma_for_population)
    else:
        # 기준선 확정 후: 최근 초과 여부 기록(최근 3일만 유지)
        state.recent_above.append(score > state.baseline_mean)
        state.recent_above = state.recent_above[-3:]

    return state


def _finalize_baseline(state: TrendState, pop_mean: float, pop_sigma: float) -> None:
    """수집한 점수와 모집단 값을 수축 결합해 기준선을 확정한다.

    개인 표본만으로 추정한 통계는 불안정하므로 모집단 값 쪽으로 끌어당긴다.
    개인 관측이 많을수록 개인 값의 비중이 커진다.(보고서 2.3)
    """
    n = len(state.baseline_scores)
    indiv_mean = sum(state.baseline_scores) / n
    indiv_var = sum((s - indiv_mean) ** 2 for s in state.baseline_scores) / max(1, n - 1)
    indiv_sigma = math.sqrt(indiv_var)

    # 평균: (n·개인 + k·모집단) / (n+k)
    state.baseline_mean = (n * indiv_mean + SHRINKAGE_K * pop_mean) / (n + SHRINKAGE_K)
    # 표준편차도 같은 방식으로 수축
    state.baseline_sigma = (n * indiv_sigma + SHRINKAGE_K * pop_sigma) / (n + SHRINKAGE_K)


def control_limit(state: TrendState) -> float | None:
    """관리 상한선(UCL). EWMA가 이 선을 넘으면 추세가 의미 있게 올라간 것.(보고서 2.3)"""
    if not state.baseline_ready:
        return None
    sigma_ewma = state.baseline_sigma * math.sqrt(LAMBDA / (2.0 - LAMBDA))
    return state.baseline_mean + L * sigma_ewma


def reset_for_new_sound() -> TrendState:
    """음원 교체 시 호출. 새 음원에 대해 빈 상태에서 다시 시작한다.(보고서 2.4)"""
    return TrendState()
