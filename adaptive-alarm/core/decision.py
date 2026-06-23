"""교체 판정 술어와 다음 음원 선택. (보고서 2.4)

교체는 여러 조건을 '동시에' 만족할 때만 제안한다. 하루이틀의 우연한 변동을
습관화로 오인하지 않기 위해 의도적으로 문턱을 겹쳐 둔다.

튜닝 가능한 상수는 core/config.py 의 Params 에 모여 있다.
"""

from __future__ import annotations

import math

from .config import DEFAULT, Params
from .models import AlarmRecord, SoundProfile
from .scoring import is_extreme_sleep_debt
from .trend import TrendState, control_limit


def should_propose_swap(
    state: TrendState,
    today: AlarmRecord,
    days_on_current_sound: int,
    days_since_last_swap: int,
    params: Params = DEFAULT,
) -> bool:
    """오늘 음원 교체를 제안할지 판정한다. 모든 조건이 참이어야 True.

    조건(보고서 2.4):
      1) 기준선이 확정되어 있고 EWMA가 관리 상한선을 넘었다.
      2) 최근 N일 연속으로 점수가 기준선을 웃돌았다(N = consecutive_above).
      3) 현재 음원으로 충분히 오래 관찰했다(기준선 확정 이후).
      4) 마지막 교체로부터 최소 간격이 지났다.
      5) 오늘이 극단적 수면 부족이 아니다(그 상승은 습관화가 아닐 가능성이 큼).
    """
    if not state.baseline_ready:
        return False

    ucl = control_limit(state, params)
    if ucl is None or state.ewma is None or state.ewma <= ucl:
        return False

    need = params.consecutive_above
    if len(state.recent_above) < need or not all(state.recent_above):
        return False

    if days_on_current_sound < 1:  # 기준선 확정 자체가 days>=baseline_days를 보장
        return False

    if days_since_last_swap < params.min_days_between_swaps:
        return False

    if is_extreme_sleep_debt(today, params):
        return False

    return True


def _distance(a: tuple[float, ...], b: tuple[float, ...]) -> float:
    """두 음향 특징 벡터 사이의 유클리드 거리."""
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def select_next_sound(
    current: SoundProfile,
    catalog: list[SoundProfile],
    recently_used: list[str],
    critical_wakeup: bool = False,
) -> SoundProfile:
    """바꿀 음원을 고른다.(보고서 2.4)

    원칙:
      - 지금 음원과 음향적으로 충분히 다른 것을 우선(거리가 클수록 좋음).
      - 평상시엔 멜로디가 뚜렷한 음원을 우선(아침 몽롱함 감소).
      - 최근에 쓴 음원은 후순위로 미뤄 여러 음원이 돌아가게 함.
      - 단, critical_wakeup(지각 위험이 큰 기상)이면 부드러움보다 확실히 깨우는
        힘을 우선해 낮고 거친(harsh) 계열을 고른다.
    """
    candidates = [s for s in catalog if s.sound_id != current.sound_id]
    if not candidates:
        return current

    def score(s: SoundProfile) -> float:
        v = _distance(current.features, s.features)          # 다를수록 +
        if critical_wakeup:
            v += 2.0 if s.category == "harsh" else 0.0       # 확실히 깨우는 힘 우선
        else:
            v += s.melody_score                              # 멜로디 우선
        if s.sound_id in recently_used:
            v -= 1.0                                         # 최근 사용 후순위
        return v

    return max(candidates, key=score)
