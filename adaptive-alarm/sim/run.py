"""시뮬레이션 하니스. `python -m sim.run` 으로 실행.

두 가지를 보여준다.
  1) 한 사용자의 하루하루 추적(점수·EWMA·상한선·교체 이벤트) 텍스트 트레이스
  2) 다수 사용자에 대한 집계 지표
       - 습관화 그룹: 교체까지 걸린 평균 일수(탐지 지연), 평균 교체 횟수
       - 대조 그룹(습관화 없음): 헛 교체(오탐) 비율

evaluate() 는 sim/tune.py 의 파라미터 스윕에서도 재사용된다.
"""

from __future__ import annotations

import random
from dataclasses import dataclass

from core import scoring
from core.config import DEFAULT, Params
from core.decision import select_next_sound, should_propose_swap
from core.trend import control_limit, reset_for_new_sound, update
from sim.generate import CATALOG, CATALOG_BY_ID, SimUser, population_priors


class UserSim:
    """한 사용자에 대한 전체 시뮬레이션 진행 상태."""

    def __init__(self, user: SimUser, start_sound: str, params: Params = DEFAULT):
        self.user = user
        self.params = params
        self.current_sound = start_sound
        self.days_on_sound = 0
        self.days_since_swap = 10_000          # 처음엔 제약 없음
        self.recently_used = [start_sound]
        self.state = reset_for_new_sound()
        self.swap_days: list[int] = []         # 교체가 일어난 일자들

    def step(self, day_index: int) -> dict:
        p = self.params
        pop_mean, pop_sigma = population_priors()
        rec = self.user.make_record(day_index, self.current_sound, self.days_on_sound)
        score = scoring.deconfounded_score(rec, p)

        update(self.state, day_index, pop_mean, pop_sigma, score, p)

        proposed = should_propose_swap(
            self.state, rec,
            days_on_current_sound=self.days_on_sound,
            days_since_last_swap=self.days_since_swap,
            params=p,
        )

        row = {
            "day": day_index,
            "sound": self.current_sound,
            "active_s": scoring.active_interaction_seconds(rec),
            "snooze": scoring.snooze_count(rec),
            "score": score,
            "ewma": self.state.ewma,
            "ucl": control_limit(self.state, p),
            "swap": False,
        }

        if proposed:
            # 시뮬레이션에선 제안을 항상 수락한다고 가정(수락률은 별도 변수)
            nxt = select_next_sound(
                CATALOG_BY_ID[self.current_sound], CATALOG, self.recently_used,
                critical_wakeup=False,
            )
            self.current_sound = nxt.sound_id
            self.recently_used = (self.recently_used + [nxt.sound_id])[-3:]
            self.days_on_sound = 0
            self.days_since_swap = 0
            self.state = reset_for_new_sound()
            self.swap_days.append(day_index)
            row["swap"] = True
        else:
            self.days_on_sound += 1
            self.days_since_swap += 1

        return row


@dataclass
class Metrics:
    detect_rate: float        # 습관화 그룹 중 교체를 1회 이상 받은 비율(0~1)
    avg_first_swap: float     # 첫 교체까지 평균 일수(탐지 지연), 없으면 -1
    avg_swaps: float          # 습관화 그룹 사용자당 평균 교체 횟수
    fp_user_rate: float       # 대조 그룹 중 헛 교체 1회 이상 비율(0~1)
    fp_per_100d: float        # 대조 그룹 사용자·100일당 헛 교체 수


def evaluate(params: Params = DEFAULT, n_users: int = 300, days: int = 90) -> Metrics:
    """주어진 파라미터로 두 그룹을 시뮬레이션하고 지표를 돌려준다(재현 가능)."""
    first_swap_days: list[int] = []
    swap_counts: list[int] = []
    for i in range(n_users):
        rng = random.Random(1000 + i)
        sim = UserSim(SimUser(rng, habituates=True), "melody_a", params)
        for d in range(days):
            sim.step(d)
        if sim.swap_days:
            first_swap_days.append(sim.swap_days[0])
            swap_counts.append(len(sim.swap_days))

    control_with_swap = 0
    control_total_swaps = 0
    for i in range(n_users):
        rng = random.Random(5000 + i)
        sim = UserSim(SimUser(rng, habituates=False), "melody_a", params)
        for d in range(days):
            sim.step(d)
        if sim.swap_days:
            control_with_swap += 1
        control_total_swaps += len(sim.swap_days)

    return Metrics(
        detect_rate=len(first_swap_days) / n_users,
        avg_first_swap=(sum(first_swap_days) / len(first_swap_days)) if first_swap_days else -1.0,
        avg_swaps=(sum(swap_counts) / len(swap_counts)) if swap_counts else 0.0,
        fp_user_rate=control_with_swap / n_users,
        fp_per_100d=control_total_swaps / (n_users * days) * 100,
    )


def trace_one_user(seed: int = 7, days: int = 60, params: Params = DEFAULT) -> None:
    rng = random.Random(seed)
    user = SimUser(rng, habituates=True)
    sim = UserSim(user, "melody_a", params)

    print(f"\n{'='*72}")
    print(f"[단일 사용자 트레이스]  습관화 시정수 tau={user.hab_tau_days:.1f}일, "
          f"진폭={user.hab_amplitude:.2f}, 수면단계잡음 σ={user.sigma_stage:.2f}")
    print(f"{'='*72}")
    print(f"{'일':>3} {'음원':>9} {'활성초':>7} {'스누즈':>5} {'점수':>6} "
          f"{'EWMA':>6} {'상한선':>6}  교체")
    for d in range(days):
        r = sim.step(d)
        ucl = f"{r['ucl']:.2f}" if r["ucl"] is not None else "  -"
        ewma = f"{r['ewma']:.2f}" if r["ewma"] is not None else "  -"
        mark = " ★바꿈" if r["swap"] else ""
        print(f"{r['day']:>3} {r['sound']:>9} {r['active_s']:>7.0f} {r['snooze']:>5} "
              f"{r['score']:>6.2f} {ewma:>6} {ucl:>6}{mark}")
    print(f"\n교체가 일어난 일자: {sim.swap_days or '없음'}")


def print_metrics(m: Metrics, days: int = 90) -> None:
    print("\n■ 습관화 그룹(실제로 익숙해지는 사용자)")
    print(f"  - 교체를 한 번이라도 제안받은 비율 : {100*m.detect_rate:.0f}%")
    if m.avg_first_swap >= 0:
        print(f"  - 첫 교체까지 평균 일수(탐지 지연): {m.avg_first_swap:.1f}일")
        print(f"  - 사용자당 평균 교체 횟수        : {m.avg_swaps:.1f}회")
    print("\n■ 대조 그룹(습관화 없음 → 모든 교체가 오탐)")
    print(f"  - 헛 교체를 1회 이상 한 사용자 비율 : {100*m.fp_user_rate:.1f}%")
    print(f"  - 오탐률(사용자·100일당 헛 교체 수) : {m.fp_per_100d:.2f}회")


if __name__ == "__main__":
    trace_one_user()
    print(f"\n{'='*72}\n[집계]  기본 파라미터(DEFAULT)\n{'='*72}")
    print_metrics(evaluate())
