// 튜닝 가능한 모든 하이퍼파라미터. (Python core/config.py 의 포팅)
//
// 기본값은 sim/tune.py 스윕으로 정함: 탐지율 91% 유지하며 오탐자 35%→15%.
// 이 값들을 바꾸면 반드시 Python 쪽과 함께 바꿔 양쪽 로직을 동일하게 유지한다.

class Params {
  // --- 점수(scoring) ---
  final double snoozeWeight;
  final double sleepDebtCoef;
  final double workdayCoef;
  final double phoneDistCoef;
  final double targetSleepHours;
  final double extremeDebtHours;

  // --- 추세(trend) ---
  final double lambda; // EWMA 평활 계수
  final double l; // 관리 상한선 폭 계수 (Python의 L)
  final int baselineDays;
  final int shrinkageK;

  // --- 판정(decision) ---
  final int consecutiveAbove;
  final int minDaysBetweenSwaps;
  final int proposalSnoozeDays;

  const Params({
    this.snoozeWeight = 0.35,
    this.sleepDebtCoef = 0.08,
    this.workdayCoef = 0.10,
    this.phoneDistCoef = 0.40,
    this.targetSleepHours = 7.5,
    this.extremeDebtHours = 3.0,
    this.lambda = 0.20,
    this.l = 3.3,
    this.baselineDays = 14,
    this.shrinkageK = 7,
    this.consecutiveAbove = 4,
    this.minDaysBetweenSwaps = 14,
    this.proposalSnoozeDays = 7,
  });
}

const Params kDefaultParams = Params();
