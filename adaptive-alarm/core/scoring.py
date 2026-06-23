"""원점수 계산과 교란 보정. (보고서 2.1, 2.2)

설계 결정 두 가지가 여기에 박혀 있다.
1) '활성 상호작용 시간'만 신호로 쓴다. 스누즈 대기 시간은 각성 저항과 무관하게
   설정값으로 정해지는 잡음이므로 제외한다.
2) 활성 시간과 스누즈를 곱하지 않고 더한다. 곱셈은 한 신호가 다른 신호를 증폭해
   같은 정보를 두 번 세지만, 가산은 두 신호를 독립적으로 합쳐 중복을 피한다.

튜닝 가능한 상수는 core/config.py 의 Params 에 모여 있다.
"""

from __future__ import annotations

import math

from .config import DEFAULT, Params
from .models import AlarmRecord


def active_interaction_seconds(record: AlarmRecord) -> float:
    """사용자가 알람과 실제로 씨름한 총 시간(초). 스누즈 대기 구간은 자동 제외된다."""
    return sum(seg.action_s - seg.ring_start_s for seg in record.segments)


def snooze_count(record: AlarmRecord) -> int:
    """스누즈를 누른 횟수(마지막 해제 구간은 제외)."""
    return sum(1 for seg in record.segments if seg.action == "snooze")


def sleep_debt_hours(record: AlarmRecord, params: Params = DEFAULT) -> float:
    """목표 수면 대비 부족분(시간). 충분히 잤으면 0."""
    return max(0.0, params.target_sleep_hours - record.sleep_hours)


def raw_score(record: AlarmRecord, params: Params = DEFAULT) -> float:
    """보정 전 원점수. log(활성 시간) + 가중치·스누즈 횟수.

    기상 행동은 짧은 값에 몰리고 가끔 매우 긴 값이 나오는 치우친 분포이므로
    활성 시간에 log를 취해 분포를 안정시킨다.(보고서 2.2)
    """
    active = active_interaction_seconds(record)
    return math.log1p(active) + params.snooze_weight * snooze_count(record)


def deconfounded_score(record: AlarmRecord, params: Params = DEFAULT) -> float:
    """원점수에서 수면 부채·요일·휴대폰 거리의 영향을 빼낸 값.

    이 값이 추세 추적과 교체 판정의 입력이 된다. 보정은 완벽하지 않으며,
    가장 큰 교란인 수면 단계는 여기서 다루지 못한다(보고서 2.6에서 별도 완화).
    """
    score = raw_score(record, params)
    score -= params.sleep_debt_coef * sleep_debt_hours(record, params)
    score -= params.workday_coef * (1.0 if record.is_workday else 0.0)
    score -= params.phone_dist_coef * record.phone_distance
    return score


def is_extreme_sleep_debt(record: AlarmRecord, params: Params = DEFAULT) -> bool:
    """교체 판정에서 아예 제외해야 할 만큼 극단적으로 잠이 부족했는가.(보고서 2.4)"""
    return sleep_debt_hours(record, params) >= params.extreme_debt_hours
