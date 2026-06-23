"""파라미터 스윕. `python -m sim.tune` 으로 실행.

핵심 손잡이를 격자로 훑어 각 설정의 탐지율·탐지 지연·오탐률을 한 표로 보여준다.
목표는 '습관화는 잘 잡으면서(탐지율↑) 헛 교체는 적은(오탐↓)' 설정을 찾는 것.

오탐을 줄이는 직접적 손잡이:
  - L              ↑ → 관리 상한선이 넓어져 둔감 → 오탐↓ (탐지율도 조금↓)
  - consecutive_above ↑ → 연속 초과 조건이 빡빡 → 오탐↓ (탐지 지연↑)
  - lambda_        ↓ → EWMA가 더 매끈 → 잡음에 덜 흔들림
"""

from __future__ import annotations

import dataclasses

from core.config import DEFAULT, Params
from sim.run import evaluate


def sweep() -> None:
    # 훑을 격자: 오탐에 가장 직접적인 두 손잡이를 교차
    L_values = [2.7, 3.0, 3.3, 3.6]
    consec_values = [3, 4, 5]
    lambda_values = [0.20, 0.25]

    rows = []
    for lam in lambda_values:
        for L in L_values:
            for c in consec_values:
                p = dataclasses.replace(DEFAULT, L=L, consecutive_above=c, lambda_=lam)
                m = evaluate(p)
                rows.append((lam, L, c, m))

    print(f"\n{'='*78}")
    print("[파라미터 스윕]  습관화 300명 + 대조 300명 × 90일")
    print(f"{'='*78}")
    print(f"{'λ':>5} {'L':>5} {'연속':>4} │ {'탐지율':>7} {'첫교체일':>8} {'교체수':>6} │ "
          f"{'오탐자%':>7} {'오탐/100일':>9}")
    print(f"{'-'*78}")

    for lam, L, c, m in rows:
        first = f"{m.avg_first_swap:.1f}" if m.avg_first_swap >= 0 else "-"
        flag = ""
        # 추천 후보 표시: 탐지율 90%+ 이면서 오탐자 비율 15% 이하
        if m.detect_rate >= 0.90 and m.fp_user_rate <= 0.15:
            flag = "  ◀ 후보"
        print(f"{lam:>5.2f} {L:>5.1f} {c:>4} │ {100*m.detect_rate:>6.0f}% {first:>8} "
              f"{m.avg_swaps:>6.1f} │ {100*m.fp_user_rate:>6.1f}% {m.fp_per_100d:>9.2f}{flag}")

    # 추천 자동 선정: 오탐자 비율 12% 이하 중 탐지율 최대, 동률이면 탐지 지연 최소
    candidates = [r for r in rows if r[3].fp_user_rate <= 0.12 and r[3].detect_rate >= 0.85]
    print(f"\n{'-'*78}")
    if candidates:
        best = min(candidates, key=lambda r: (-r[3].detect_rate, r[3].avg_first_swap))
        lam, L, c, m = best
        print(f"추천 설정: λ={lam}, L={L}, consecutive_above={c}")
        print(f"  → 탐지율 {100*m.detect_rate:.0f}%, 첫 교체 {m.avg_first_swap:.1f}일, "
              f"오탐자 {100*m.fp_user_rate:.1f}%, 오탐 {m.fp_per_100d:.2f}/100일")
    else:
        print("오탐자 12% 이하 조건을 만족하는 설정이 없음. 격자를 더 넓혀야 함.")


if __name__ == "__main__":
    sweep()
