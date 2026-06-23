"""AlarmEngine 사용 예제 겸 Dart 포팅 참조.  실행: `python -m examples.engine_usage`

앱이 엔진과 주고받는 전체 흐름을 합성 데이터 없이 손으로 보여준다.
이 시나리오 그대로 Dart에서 재현하면 포팅이 맞는지 대조할 수 있다.
"""

from __future__ import annotations

import json

from core.engine import AlarmEngine
from core.events import build_record
from core.models import SoundProfile

# 앱이 들고 있을 음원 카탈로그
CATALOG = [
    SoundProfile("morning_bells", 0.9, (0.6, 0.7, 0.8), "melodic"),
    SoundProfile("classic_beep", 0.2, (0.5, 0.9, 0.5), "beep"),
    SoundProfile("deep_horn", 0.1, (0.3, 0.1, 0.2), "harsh"),
    SoundProfile("piano_rise", 0.85, (0.7, 0.5, 0.9), "melodic"),
]


def main() -> None:
    # 1) 새 사용자: 시작 음원으로 엔진 생성
    eng = AlarmEngine.new(CATALOG, start_sound="morning_bells")
    print("새 엔진 생성. 현재 음원:", eng.state.current_sound)

    # 2) 매일 알람이 끝나면 원시 이벤트로 기록을 만들어 넣는다.
    #    여기서는 점점 깨기 힘들어지는(활성 시간이 늘어나는) 사용자를 흉내.
    last_proposal = None
    for day in range(40):
        active = 25 if day < 14 else 25 + 10 * (day - 14)  # 기준선 후 상승
        rec = build_record(
            day_index=day,
            sound_id=eng.state.current_sound,
            interactions=[(0.0, float(active), "dismiss")],
            sleep_hours=7.4,
            is_workday=(day % 7) < 5,
        )
        proposal = eng.record_alarm(rec)

        # 3) 하루가 끝날 때마다 상태를 JSON으로 저장(앱은 기기 저장소에).
        saved = json.dumps(eng.to_dict())

        # 4) 다음 날 앱이 다시 켜지면 저장된 상태에서 복원.
        eng = AlarmEngine.from_dict(CATALOG, json.loads(saved))

        if proposal.propose:
            last_proposal = (day, proposal)
            print(f"\n[{day}일] 교체 제안!  {proposal.from_sound} → {proposal.to_sound}")
            print(f"        사유: {proposal.reason}")
            break

    if last_proposal is None:
        print("40일 안에 교체 제안 없음.")
        return

    # 5) 사용자가 수락 → 엔진이 새 음원으로 전환하고 추세를 리셋.
    day, proposal = last_proposal
    eng.accept_swap(proposal.to_sound)
    print(f"\n사용자가 수락. 현재 음원: {eng.state.current_sound}, "
          f"days_on_sound={eng.state.days_on_sound}(리셋됨)")
    print("최근 사용 음원:", eng.state.recently_used)

    # (대안) 거절했다면:  eng.decline_swap()  → proposal_snooze_days 동안 다시 제안 안 함
    print("\n저장 상태(JSON) 미리보기:")
    print(json.dumps(eng.to_dict(), ensure_ascii=False)[:200] + " ...")


if __name__ == "__main__":
    main()
