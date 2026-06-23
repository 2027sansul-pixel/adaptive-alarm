// 추세 추적: 시간감쇠 EWMA, 음원별 기준선, 관리 상한선. (Python core/trend.py 포팅)

import 'dart:math' as math;

import 'config.dart';

/// 한 사용자 × 한 음원 조합의 추세 상태.
class TrendState {
  double? ewma;
  int? lastDayIndex;
  List<double> baselineScores;
  double? baselineMean;
  double? baselineSigma;
  List<bool> recentAbove;

  TrendState({
    this.ewma,
    this.lastDayIndex,
    List<double>? baselineScores,
    this.baselineMean,
    this.baselineSigma,
    List<bool>? recentAbove,
  })  : baselineScores = baselineScores ?? <double>[],
        recentAbove = recentAbove ?? <bool>[];

  bool get baselineReady => baselineMean != null;
}

TrendState resetForNewSound() => TrendState();

/// 달력 간격을 반영한 유효 평활 계수. gap=1이면 lambda, 커질수록 1에 수렴.
double ewmaAlphaForGap(int gapDays, Params p) {
  final gap = gapDays < 1 ? 1 : gapDays;
  return 1.0 - math.pow(1.0 - p.lambda, gap).toDouble();
}

/// 하루치 보정 점수로 추세 상태를 갱신한다.
void update(TrendState st, int dayIndex, double popMean, double popSigma,
    double score, [Params p = kDefaultParams]) {
  // 1) 시간감쇠 EWMA
  if (st.ewma == null) {
    st.ewma = score;
  } else {
    final prev = st.lastDayIndex ?? dayIndex;
    final alpha = ewmaAlphaForGap(dayIndex - prev, p);
    st.ewma = alpha * score + (1.0 - alpha) * st.ewma!;
  }
  st.lastDayIndex = dayIndex;

  // 2) 기준선 수집/확정
  if (!st.baselineReady) {
    st.baselineScores.add(score);
    if (st.baselineScores.length >= p.baselineDays) {
      _finalizeBaseline(st, popMean, popSigma, p);
    }
  } else {
    st.recentAbove.add(score > st.baselineMean!);
    if (st.recentAbove.length > p.consecutiveAbove) {
      st.recentAbove =
          st.recentAbove.sublist(st.recentAbove.length - p.consecutiveAbove);
    }
  }
}

void _finalizeBaseline(
    TrendState st, double popMean, double popSigma, Params p) {
  final n = st.baselineScores.length;
  final indivMean = st.baselineScores.reduce((a, b) => a + b) / n;
  var ss = 0.0;
  for (final s in st.baselineScores) {
    ss += (s - indivMean) * (s - indivMean);
  }
  final indivVar = ss / math.max(1, n - 1);
  final indivSigma = math.sqrt(indivVar);

  final k = p.shrinkageK;
  st.baselineMean = (n * indivMean + k * popMean) / (n + k);
  st.baselineSigma = (n * indivSigma + k * popSigma) / (n + k);
}

/// 관리 상한선(UCL). EWMA가 이 선을 넘으면 추세가 의미 있게 올라간 것.
double? controlLimit(TrendState st, [Params p = kDefaultParams]) {
  if (!st.baselineReady) return null;
  final sigmaEwma = st.baselineSigma! * math.sqrt(p.lambda / (2.0 - p.lambda));
  return st.baselineMean! + p.l * sigmaEwma;
}
