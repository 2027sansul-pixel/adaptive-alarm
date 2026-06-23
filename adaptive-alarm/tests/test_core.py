"""core/ 단위 테스트 및 골든(parity) 테스트.  실행: `python -m unittest -v`

골든 테스트는 고정된 입력에 대한 기대 출력을 박아둔다. Dart 포팅 시 같은 입력에
같은 수를 내는지 대조하는 기준이 된다.
"""

from __future__ import annotations

import math
import unittest

from core import scoring
from core.config import DEFAULT, Params
from core.engine import AlarmEngine
from core.events import build_record, is_workday
from core.models import AlarmRecord, AlarmSegment, SoundProfile
from core.trend import TrendState, control_limit, reset_for_new_sound, update


def _rec(active_segments, snooze=0, **ctx):
    """간단 헬퍼: 활성 시간 목록으로 AlarmRecord 만들기(스누즈 대기는 큰 간격으로)."""
    segs = []
    t = 0.0
    n = len(active_segments)
    for i, dur in enumerate(active_segments):
        action = "dismiss" if i == n - 1 else "snooze"
        segs.append(AlarmSegment(ring_start_s=t, action_s=t + dur, action=action))
        t += dur + 540  # 9분 스누즈 대기(활성 시간에 포함되면 안 됨)
    return AlarmRecord(day_index=ctx.get("day_index", 0), sound_id="s", segments=segs,
                       sleep_hours=ctx.get("sleep_hours", 7.5),
                       is_workday=ctx.get("is_workday", True),
                       phone_distance=ctx.get("phone_distance", 0.0))


class TestScoring(unittest.TestCase):
    def test_active_time_excludes_snooze_wait(self):
        # 40초+30초+50초 활성, 사이에 9분 대기 두 번 → 활성은 120초여야 함
        rec = _rec([40, 30, 50])
        self.assertEqual(scoring.active_interaction_seconds(rec), 120)
        self.assertEqual(scoring.snooze_count(rec), 2)

    def test_raw_score_is_additive(self):
        # 같은 활성 시간이면 스누즈 1회당 정확히 snooze_weight 만큼만 늘어야 함(곱셈 아님)
        a = _rec([100])            # 스누즈 0
        b = _rec([60, 40])         # 활성 동일(100), 스누즈 1
        delta = scoring.raw_score(b) - scoring.raw_score(a)
        self.assertAlmostEqual(delta, DEFAULT.snooze_weight, places=9)

    def test_deconfound_subtracts_factors(self):
        base = _rec([100], sleep_hours=7.5, is_workday=False, phone_distance=0.0)
        debt = _rec([100], sleep_hours=5.5, is_workday=False, phone_distance=0.0)
        # 2시간 부족 → sleep_debt_coef * 2 만큼 점수가 낮아져야 함
        diff = scoring.deconfounded_score(base) - scoring.deconfounded_score(debt)
        self.assertAlmostEqual(diff, DEFAULT.sleep_debt_coef * 2.0, places=9)

    def test_extreme_sleep_debt_flag(self):
        self.assertTrue(scoring.is_extreme_sleep_debt(_rec([10], sleep_hours=4.0)))
        self.assertFalse(scoring.is_extreme_sleep_debt(_rec([10], sleep_hours=7.0)))


class TestEvents(unittest.TestCase):
    def test_build_and_validate(self):
        rec = build_record(day_index=3, sound_id="s",
                           interactions=[(0, 40, "snooze"), (580, 620, "dismiss")],
                           sleep_hours=7.0, is_workday=True)
        self.assertEqual(scoring.active_interaction_seconds(rec), 80)  # 40 + 40

    def test_rejects_non_dismiss_end(self):
        with self.assertRaises(ValueError):
            build_record(day_index=0, sound_id="s",
                         interactions=[(0, 40, "snooze")],
                         sleep_hours=7.0, is_workday=True)

    def test_rejects_action_before_ring(self):
        with self.assertRaises(ValueError):
            build_record(day_index=0, sound_id="s",
                         interactions=[(100, 50, "dismiss")],
                         sleep_hours=7.0, is_workday=True)

    def test_is_workday(self):
        self.assertTrue(is_workday(0))   # 월
        self.assertFalse(is_workday(5))  # 토


class TestTrend(unittest.TestCase):
    def test_ewma_gap_decay(self):
        # 간격이 클수록 새 값에 더 큰 가중치(유효 alpha가 커짐)
        from core.trend import _ewma_alpha_for_gap
        a1 = _ewma_alpha_for_gap(1, DEFAULT)
        a3 = _ewma_alpha_for_gap(3, DEFAULT)
        self.assertAlmostEqual(a1, DEFAULT.lambda_, places=9)
        self.assertGreater(a3, a1)

    def test_baseline_finalizes_after_n_days(self):
        st = reset_for_new_sound()
        for d in range(DEFAULT.baseline_days):
            update(st, d, 3.6, 0.7, 4.0, DEFAULT)
        self.assertTrue(st.baseline_ready)
        self.assertIsNotNone(control_limit(st, DEFAULT))

    def test_control_limit_above_mean(self):
        st = reset_for_new_sound()
        for d in range(DEFAULT.baseline_days):
            update(st, d, 3.6, 0.7, 4.0 + 0.1 * (d % 3), DEFAULT)
        self.assertGreater(control_limit(st, DEFAULT), st.baseline_mean)


class TestEngine(unittest.TestCase):
    CATALOG = [
        SoundProfile("a", 0.9, (0.6, 0.7, 0.8), "melodic"),
        SoundProfile("b", 0.8, (0.1, 0.2, 0.1), "harsh"),
        SoundProfile("c", 0.85, (0.7, 0.5, 0.9), "melodic"),
    ]

    def _escalating_record(self, day, sound, active):
        return build_record(day_index=day, sound_id=sound,
                            interactions=[(0, active, "dismiss")],
                            sleep_hours=7.5, is_workday=True)

    def test_escalation_triggers_proposal(self):
        eng = AlarmEngine.new(self.CATALOG, "a")
        proposed_day = None
        for d in range(60):
            # 기준선 구간은 낮게, 이후 점점 높여 습관화를 흉내
            active = 30 if d < DEFAULT.baseline_days else 30 + 12 * (d - DEFAULT.baseline_days)
            p = eng.record_alarm(self._escalating_record(d, eng.state.current_sound, active))
            if p.propose:
                proposed_day = d
                self.assertEqual(p.from_sound, "a")
                self.assertIsNotNone(p.to_sound)
                break
        self.assertIsNotNone(proposed_day, "상승 추세인데도 교체가 제안되지 않음")

    def test_accept_resets_and_switches(self):
        eng = AlarmEngine.new(self.CATALOG, "a")
        eng.accept_swap("b")
        self.assertEqual(eng.state.current_sound, "b")
        self.assertEqual(eng.state.days_on_sound, 0)
        self.assertEqual(eng.state.days_since_swap, 0)
        self.assertIn("b", eng.state.recently_used)

    def test_decline_starts_cooldown(self):
        eng = AlarmEngine.new(self.CATALOG, "a")
        # 강제로 제안 가능한 상태를 만든 뒤 거절하면 쿨다운 동안 제안 안 함
        for d in range(DEFAULT.baseline_days):
            eng.record_alarm(self._escalating_record(d, "a", 30))
        eng.decline_swap()
        self.assertEqual(eng.state.days_since_decline, 0)
        p = eng.record_alarm(self._escalating_record(DEFAULT.baseline_days, "a", 999))
        self.assertFalse(p.propose)  # 쿨다운 중이라 제안 안 됨

    def test_serialization_roundtrip(self):
        eng = AlarmEngine.new(self.CATALOG, "a")
        for d in range(20):
            eng.record_alarm(self._escalating_record(d, eng.state.current_sound, 30 + d))
        data = eng.to_dict()
        # JSON 직렬화/역직렬화가 실제로 되는지
        import json
        restored = AlarmEngine.from_dict(self.CATALOG, json.loads(json.dumps(data)))
        self.assertEqual(restored.state.current_sound, eng.state.current_sound)
        self.assertEqual(restored.state.days_on_sound, eng.state.days_on_sound)
        self.assertEqual(restored.current_trend().ewma, eng.current_trend().ewma)


class TestGoldenParity(unittest.TestCase):
    """Dart 포팅 대조용 고정 수치. 로직을 의도적으로 바꿀 때만 이 값을 갱신한다."""

    def test_known_active_time_and_score(self):
        rec = build_record(day_index=0, sound_id="s",
                           interactions=[(0, 45, "snooze"), (585, 615, "snooze"), (1155, 1205, "dismiss")],
                           sleep_hours=6.5, is_workday=True, phone_distance=0.0)
        self.assertEqual(scoring.active_interaction_seconds(rec), 125)   # 45+30+50
        self.assertEqual(scoring.snooze_count(rec), 2)
        # raw = log1p(125) + 0.35*2 ; deconfound: -0.08*1.0(수면부채1h) -0.10(근무일)
        expected_raw = math.log1p(125) + DEFAULT.snooze_weight * 2
        self.assertAlmostEqual(scoring.raw_score(rec), expected_raw, places=9)
        expected_dec = expected_raw - DEFAULT.sleep_debt_coef * 1.0 - DEFAULT.workday_coef
        self.assertAlmostEqual(scoring.deconfounded_score(rec), expected_dec, places=9)

    def test_known_ewma_sequence(self):
        # λ=0.20 고정 가정. 첫 값 5.0, 이후 6.0을 간격1로 두 번.
        p = Params(lambda_=0.20)
        st = TrendState()
        update(st, 0, 3.6, 0.7, 5.0, p)
        update(st, 1, 3.6, 0.7, 6.0, p)
        update(st, 2, 3.6, 0.7, 6.0, p)
        # 5.0 → 0.2*6+0.8*5=5.2 → 0.2*6+0.8*5.2=5.36
        self.assertAlmostEqual(st.ewma, 5.36, places=9)


if __name__ == "__main__":
    unittest.main()
