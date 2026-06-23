"""AlarmEngine: 시스템의 핵심 facade. 앱(Dart)이 그대로 미러링할 대상.

흐름:
  1) 매일 알람이 끝나면 record_alarm(record)를 호출한다.
  2) 엔진은 현재 음원의 추세를 갱신하고, 교체를 제안할지 판정해 SwapProposal을 돌려준다.
  3) 사용자가 수락하면 accept_swap(), 거절하면 decline_swap()을 호출한다.
     - 강제로 바꾸지 않는다. 교체는 항상 '제안'이다.(보고서 2.4)
     - 거절하면 일정 기간(proposal_snooze_days) 다시 제안하지 않는다.

상태는 사용자별로 보관되며 to_dict()/from_dict()로 JSON 직렬화할 수 있다.
앱은 이 dict를 기기에 저장했다가 다음 날 복원한다.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .config import DEFAULT, Params
from .decision import select_next_sound, should_propose_swap
from .models import AlarmRecord, SoundProfile
from .scoring import deconfounded_score
from .trend import TrendState, control_limit, reset_for_new_sound, update

# 데이터가 없는 음원의 콜드스타트용 모집단 기준선 기본값 (보정 점수 스케일)
DEFAULT_PRIOR = (3.6, 0.7)

_BIG = 10_000  # '아주 오래전'을 뜻하는 초기 카운터 값


@dataclass
class SwapProposal:
    """record_alarm의 결과. propose=False면 나머지 필드는 의미 없다."""

    propose: bool
    from_sound: str
    to_sound: str | None = None
    reason: str = ""


@dataclass
class EngineState:
    """직렬화되는 사용자별 진행 상태."""

    current_sound: str
    days_on_sound: int = 0
    days_since_swap: int = _BIG
    days_since_decline: int = _BIG
    recently_used: list[str] = field(default_factory=list)
    # 음원 ID -> 그 음원에 대한 TrendState
    trends: dict[str, TrendState] = field(default_factory=dict)


class AlarmEngine:
    def __init__(
        self,
        catalog: list[SoundProfile],
        state: EngineState,
        *,
        params: Params = DEFAULT,
        priors: dict[str, tuple[float, float]] | None = None,
    ):
        self.catalog_list = list(catalog)
        self.catalog = {s.sound_id: s for s in catalog}
        self.params = params
        self.priors = priors or {}
        self.state = state
        if state.current_sound not in self.catalog:
            raise ValueError(f"카탈로그에 없는 음원: {state.current_sound}")

    # ---- 생성/복원 --------------------------------------------------------
    @classmethod
    def new(cls, catalog: list[SoundProfile], start_sound: str,
            *, params: Params = DEFAULT,
            priors: dict[str, tuple[float, float]] | None = None) -> "AlarmEngine":
        state = EngineState(current_sound=start_sound, recently_used=[start_sound])
        return cls(catalog, state, params=params, priors=priors)

    # ---- 메인 진입점 ------------------------------------------------------
    def record_alarm(self, record: AlarmRecord) -> SwapProposal:
        """오늘의 알람 기록을 받아 추세를 갱신하고 교체 제안 여부를 돌려준다."""
        s = self.state
        sound = s.current_sound
        trend = s.trends.setdefault(sound, reset_for_new_sound())

        pop_mean, pop_sigma = self.priors.get(sound, DEFAULT_PRIOR)
        score = deconfounded_score(record, self.params)
        update(trend, record.day_index, pop_mean, pop_sigma, score, self.params)

        proposal = self._decide(record)

        # 하루가 지났으므로 카운터를 진행시킨다(수락/거절은 별도 호출에서 리셋).
        s.days_on_sound += 1
        s.days_since_swap += 1
        s.days_since_decline += 1
        return proposal

    def _decide(self, record: AlarmRecord) -> SwapProposal:
        s = self.state
        trend = s.trends[s.current_sound]

        # 최근에 거절했다면 쿨다운 동안 제안하지 않는다.
        if s.days_since_decline < self.params.proposal_snooze_days:
            return SwapProposal(False, s.current_sound, reason="거절 쿨다운 중")

        if not should_propose_swap(
            trend, record,
            days_on_current_sound=s.days_on_sound,
            days_since_last_swap=s.days_since_swap,
            params=self.params,
        ):
            return SwapProposal(False, s.current_sound)

        nxt = select_next_sound(
            self.catalog[s.current_sound], self.catalog_list, s.recently_used,
            critical_wakeup=False,
        )
        return SwapProposal(
            True, s.current_sound, nxt.sound_id,
            reason="추세가 관리 상한선을 넘고 연속 초과 조건을 만족함",
        )

    # ---- 사용자 응답 ------------------------------------------------------
    def accept_swap(self, to_sound: str) -> None:
        """사용자가 교체를 수락. 새 음원으로 바꾸고 추세를 처음부터 다시 모은다."""
        if to_sound not in self.catalog:
            raise ValueError(f"카탈로그에 없는 음원: {to_sound}")
        s = self.state
        s.current_sound = to_sound
        s.recently_used = (s.recently_used + [to_sound])[-3:]
        s.days_on_sound = 0
        s.days_since_swap = 0
        s.days_since_decline = _BIG
        s.trends[to_sound] = reset_for_new_sound()

    def decline_swap(self) -> None:
        """사용자가 제안을 거절. 쿨다운을 시작해 한동안 다시 제안하지 않는다."""
        self.state.days_since_decline = 0

    # ---- 내부 상태 조회(트레이스/디버깅용) --------------------------------
    def current_trend(self) -> TrendState:
        return self.state.trends.setdefault(self.state.current_sound, reset_for_new_sound())

    def current_control_limit(self) -> float | None:
        return control_limit(self.current_trend(), self.params)

    # ---- 직렬화 -----------------------------------------------------------
    def to_dict(self) -> dict:
        """기기 저장용 JSON 직렬화 가능한 dict."""
        s = self.state
        return {
            "current_sound": s.current_sound,
            "days_on_sound": s.days_on_sound,
            "days_since_swap": s.days_since_swap,
            "days_since_decline": s.days_since_decline,
            "recently_used": list(s.recently_used),
            "trends": {sid: _trend_to_dict(t) for sid, t in s.trends.items()},
        }

    @classmethod
    def from_dict(cls, catalog: list[SoundProfile], data: dict,
                  *, params: Params = DEFAULT,
                  priors: dict[str, tuple[float, float]] | None = None) -> "AlarmEngine":
        state = EngineState(
            current_sound=data["current_sound"],
            days_on_sound=data["days_on_sound"],
            days_since_swap=data["days_since_swap"],
            days_since_decline=data["days_since_decline"],
            recently_used=list(data["recently_used"]),
            trends={sid: _trend_from_dict(d) for sid, d in data["trends"].items()},
        )
        return cls(catalog, state, params=params, priors=priors)


def _trend_to_dict(t: TrendState) -> dict:
    return {
        "ewma": t.ewma,
        "last_day_index": t.last_day_index,
        "baseline_scores": list(t.baseline_scores),
        "baseline_mean": t.baseline_mean,
        "baseline_sigma": t.baseline_sigma,
        "recent_above": list(t.recent_above),
    }


def _trend_from_dict(d: dict) -> TrendState:
    return TrendState(
        ewma=d["ewma"],
        last_day_index=d["last_day_index"],
        baseline_scores=list(d["baseline_scores"]),
        baseline_mean=d["baseline_mean"],
        baseline_sigma=d["baseline_sigma"],
        recent_above=list(d["recent_above"]),
    )
