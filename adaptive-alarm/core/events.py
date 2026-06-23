"""원시 알람 상호작용을 AlarmRecord로 변환한다.

앱(Dart)은 알람이 울릴 때마다 (울린 시각, 사용자가 누른 시각, 누른 종류)를
기록한다. 이 모듈은 그 원시 이벤트 목록과 그날의 맥락을 받아, core/ 의 점수
함수가 소비하는 AlarmRecord로 조립하고 기본적인 유효성 검사를 한다.
"""

from __future__ import annotations

from .models import AlarmRecord, AlarmSegment

# 한 번의 알람 상호작용: (울리기 시작한 에포크 초, 조작한 에포크 초, 'snooze'|'dismiss')
Interaction = tuple[float, float, str]


def is_workday(weekday: int) -> bool:
    """월=0 ... 일=6. 월~금을 근무일로 본다. 앱에서 사용자 설정으로 덮어쓸 수 있다."""
    return weekday < 5


def build_record(
    *,
    day_index: int,
    sound_id: str,
    interactions: list[Interaction],
    sleep_hours: float,
    is_workday: bool,
    phone_distance: float = 0.0,
    alarm_hour: float = 7.0,
) -> AlarmRecord:
    """원시 상호작용 목록을 검증해 AlarmRecord로 만든다.

    검증 규칙:
      - 적어도 하나의 상호작용이 있어야 한다.
      - 각 구간은 누른 시각이 울린 시각보다 같거나 뒤여야 한다.
      - 구간은 시간순으로 정렬되어 있어야 한다.
      - 마지막 구간은 반드시 'dismiss'(완전히 끔)여야 한다.
    """
    if not interactions:
        raise ValueError("상호작용이 비어 있습니다. 최소 한 번의 해제가 필요합니다.")

    segments: list[AlarmSegment] = []
    prev_action_s: float | None = None
    for ring_s, action_s, action in interactions:
        if action_s < ring_s:
            raise ValueError(f"누른 시각({action_s})이 울린 시각({ring_s})보다 빠릅니다.")
        if prev_action_s is not None and ring_s < prev_action_s:
            raise ValueError("구간이 시간순으로 정렬되어 있지 않습니다.")
        if action not in ("snooze", "dismiss"):
            raise ValueError(f"알 수 없는 조작 종류: {action!r}")
        segments.append(AlarmSegment(ring_start_s=ring_s, action_s=action_s, action=action))
        prev_action_s = action_s

    if segments[-1].action != "dismiss":
        raise ValueError("마지막 구간은 반드시 'dismiss'여야 합니다.")
    if not 0.0 <= phone_distance <= 1.0:
        raise ValueError("phone_distance는 0~1 범위여야 합니다.")

    return AlarmRecord(
        day_index=day_index,
        sound_id=sound_id,
        segments=segments,
        sleep_hours=sleep_hours,
        is_workday=is_workday,
        phone_distance=phone_distance,
        alarm_hour=alarm_hour,
    )
