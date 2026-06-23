"""자료구조 정의. 앱과 시뮬레이터가 공유한다."""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class AlarmSegment:
    """알람이 한 번 울린 구간. 스누즈를 N번 누르면 한 기록에 N+1개의 구간이 생긴다.

    핵심: ring_start_s ~ action_s 사이만 '사용자가 알람과 실제로 씨름한 시간'이다.
    스누즈를 누른 뒤 다시 울리기까지의 수면 대기 시간(보통 5~9분)은 구간 사이의
    빈 공간으로 남고, 어떤 활성 시간에도 포함되지 않는다. (보고서 2.1)
    """

    ring_start_s: float  # 이 구간에서 알람이 울리기 시작한 시각(에포크 초)
    action_s: float      # 사용자가 조작(스누즈/해제)한 시각(에포크 초)
    action: str          # 'snooze' 또는 'dismiss'


@dataclass
class AlarmRecord:
    """알람 한 번(=하루 한 번의 기상)에 대한 전체 기록."""

    day_index: int                 # 0부터 시작하는 일자 인덱스(달력 간격 계산용)
    sound_id: str                  # 그날 쓴 음원 ID
    segments: list[AlarmSegment] = field(default_factory=list)

    # 보조 정보(점수에서 잡음을 걷어내는 데 쓰임, 보고서 2.1)
    sleep_hours: float = 7.0       # 전날 대략 수면 시간(초기엔 거친 추정값)
    is_workday: bool = True        # 근무일 여부(요일 효과)
    phone_distance: float = 0.0    # 0~1, 휴대폰을 멀리 둘수록 1
    alarm_hour: float = 7.0        # 알람이 울린 시각(시 단위). 같은 시각 유도 점검용


@dataclass
class SoundProfile:
    """알람음 한 종류에 대한 음향 메타데이터. (보고서 2.1, 2.4)"""

    sound_id: str
    melody_score: float            # 0~1, 멜로디에 가까울수록 1
    features: tuple[float, ...]    # 템포·음높이·밝기 등 정규화된 음향 특징 벡터
    category: str                  # 'melodic' | 'beep' | 'harsh'(낮고 거친 계열)
