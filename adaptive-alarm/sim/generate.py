"""합성 사용자와 알람 기록 생성기.

여기서 '정답(ground truth)'을 우리가 직접 만든다. 각 사용자에게 알려진 습관화
곡선을 심고, 거기에 현실적인 잡음(수면 단계·수면 부채·요일)을 얹는다. 그런 다음
core/ 알고리즘이 이 잡음 속에서 우리가 심어둔 습관화를 도로 찾아내는지 본다.

핵심 긴장(보고서 1.1, 2.6): 수면 단계 잡음의 크기를 습관화 신호와 비슷하거나
더 크게 둘 수 있다. 그래야 '수면 단계를 통제하지 않으면 추세가 묻히는가'라는
가장 위험한 질문을 정직하게 시험할 수 있다.
"""

from __future__ import annotations

import math
import random

from core.models import AlarmRecord, AlarmSegment, SoundProfile

# ---- 음원 카탈로그(시뮬레이션용) -------------------------------------------
# features = (tempo, pitch, brightness) 정규화 0~1
CATALOG: list[SoundProfile] = [
    SoundProfile("melody_a", melody_score=0.9, features=(0.6, 0.7, 0.8), category="melodic"),
    SoundProfile("melody_b", melody_score=0.8, features=(0.4, 0.6, 0.7), category="melodic"),
    SoundProfile("beep_a",   melody_score=0.2, features=(0.5, 0.9, 0.5), category="beep"),
    SoundProfile("harsh_a",  melody_score=0.1, features=(0.3, 0.1, 0.2), category="harsh"),
    SoundProfile("melody_c", melody_score=0.85, features=(0.7, 0.5, 0.9), category="melodic"),
]


def _catalog_by_id() -> dict[str, SoundProfile]:
    return {s.sound_id: s for s in CATALOG}


class SimUser:
    """한 명의 합성 사용자. 알려진 습관화 파라미터를 가진다."""

    def __init__(self, rng: random.Random, *, habituates: bool = True):
        self.rng = rng
        self.habituates = habituates

        # 개인 기본 각성 저항(사람마다 다름). 활성 시간의 로그 베이스라인.
        self.base_log_active = rng.uniform(3.0, 4.0)   # log초; e^3.5 ≈ 33초

        # 습관화 진폭과 시정수. '며칠 만에 얼마나 익숙해지는가'의 정답.
        self.hab_amplitude = rng.uniform(0.8, 1.4) if habituates else 0.0  # 로그 점수 증가량
        self.hab_tau_days = rng.uniform(2.5, 4.0)      # 시정수(보고서의 2~5일 가설 범위)

        # 잡음 크기
        self.sigma_stage = rng.uniform(0.5, 0.9)       # ★ 수면 단계 운(가장 큰 교란)
        self.sigma_misc = 0.2                          # 기타 측정 잡음
        self.snooze_base = rng.uniform(0.3, 1.2)       # 평소 스누즈 성향

    def latent_resistance(self, days_on_sound: int) -> float:
        """현재 음원을 며칠째 쓰는가에 따른 '진짜' 습관화 누적(로그 점수 증가분)."""
        if not self.habituates:
            return 0.0
        return self.hab_amplitude * (1.0 - math.exp(-days_on_sound / self.hab_tau_days))

    def make_record(self, day_index: int, sound_id: str, days_on_sound: int) -> AlarmRecord:
        """하루치 알람 기록을 합성한다."""
        rng = self.rng
        is_workday = (day_index % 7) < 5

        # 수면 시간: 근무일은 조금 부족하게, 가끔 크게 부족한 날
        sleep = rng.gauss(7.2 if is_workday else 8.0, 0.8)
        if rng.random() < 0.08:
            sleep -= rng.uniform(2.0, 4.0)             # 가끔 극단적 수면 부족
        sleep = max(3.0, sleep)
        sleep_debt = max(0.0, 7.5 - sleep)

        phone_distance = rng.choice([0.0, 0.0, 0.3, 0.7])  # 대부분 가까이, 가끔 멀리

        # ---- 진짜 활성 시간(로그) 구성 ----
        log_active = self.base_log_active
        log_active += self.latent_resistance(days_on_sound)        # ★ 습관화 신호
        log_active += rng.gauss(0.0, self.sigma_stage)             # ★ 수면 단계 운(교란)
        log_active += 0.10 * sleep_debt                            # 수면 부채 효과
        log_active += 0.10 * (1.0 if is_workday else 0.0)          # 요일 효과
        log_active += 0.40 * phone_distance                        # 휴대폰 거리 효과
        log_active += rng.gauss(0.0, self.sigma_misc)              # 기타 잡음

        total_active = math.exp(log_active)                        # 초 단위 총 활성 시간

        # ---- 스누즈 횟수: 저항이 클수록, 잠이 부족할수록 증가 ----
        snooze_lambda = self.snooze_base + 0.4 * self.latent_resistance(days_on_sound) + 0.15 * sleep_debt
        n_snooze = _poisson(rng, snooze_lambda)

        # ---- 총 활성 시간을 (스누즈+1)개 구간으로 쪼개 AlarmSegment 생성 ----
        segments = _split_into_segments(rng, total_active, n_snooze, base_epoch=day_index * 86400)

        return AlarmRecord(
            day_index=day_index,
            sound_id=sound_id,
            segments=segments,
            sleep_hours=sleep,
            is_workday=is_workday,
            phone_distance=phone_distance,
            alarm_hour=7.0,
        )


def _split_into_segments(rng: random.Random, total_active: float, n_snooze: int,
                         base_epoch: float) -> list[AlarmSegment]:
    """총 활성 시간을 n_snooze+1개 구간으로 쪼갠다. 구간 사이엔 스누즈 대기(잡음)를 끼운다."""
    n_seg = n_snooze + 1
    # 각 구간 활성 시간을 무작위 비율로 분배
    weights = [rng.uniform(0.5, 1.5) for _ in range(n_seg)]
    wsum = sum(weights)
    durations = [total_active * w / wsum for w in weights]

    segments: list[AlarmSegment] = []
    t = base_epoch + 7 * 3600  # 오전 7시
    for i, dur in enumerate(durations):
        action = "dismiss" if i == n_seg - 1 else "snooze"
        segments.append(AlarmSegment(ring_start_s=t, action_s=t + dur, action=action))
        t += dur
        if action == "snooze":
            t += 9 * 60  # 9분 스누즈 대기(활성 시간에 포함되면 안 되는 잡음)
    return segments


def _poisson(rng: random.Random, lam: float) -> int:
    """간단한 포아송 표본(Knuth)."""
    lam = max(0.0, lam)
    L = math.exp(-lam)
    k = 0
    p = 1.0
    while True:
        k += 1
        p *= rng.random()
        if p <= L:
            return k - 1


def population_priors() -> tuple[float, float]:
    """모집단 기준선의 (평균, 표준편차) 추정값. 콜드스타트용.

    실제 앱에선 같은 음원을 쓰는 다른 사용자에서 집계하지만, 시뮬레이션에선
    합리적인 고정값을 쓴다. (raw 보정 점수 스케일에 맞춤)
    """
    return (3.6, 0.7)


CATALOG_BY_ID = _catalog_by_id()
