// 교체 판정 술어와 다음 음원 선택. (Python core/decision.py 포팅)

import 'dart:math' as math;

import 'config.dart';
import 'models.dart';
import 'scoring.dart';
import 'trend.dart';

/// 오늘 음원 교체를 제안할지 판정. 모든 조건이 참이어야 true.
bool shouldProposeSwap(
  TrendState st,
  AlarmRecord today, {
  required int daysOnCurrentSound,
  required int daysSinceLastSwap,
  Params params = kDefaultParams,
}) {
  if (!st.baselineReady) return false;

  final ucl = controlLimit(st, params);
  if (ucl == null || st.ewma == null || st.ewma! <= ucl) return false;

  final need = params.consecutiveAbove;
  if (st.recentAbove.length < need || st.recentAbove.any((b) => !b)) {
    return false;
  }

  if (daysOnCurrentSound < 1) return false;
  if (daysSinceLastSwap < params.minDaysBetweenSwaps) return false;
  if (isExtremeSleepDebt(today, params)) return false;

  return true;
}

double _distance(List<double> a, List<double> b) {
  var s = 0.0;
  final n = math.min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    final d = a[i] - b[i];
    s += d * d;
  }
  return math.sqrt(s);
}

/// 바꿀 음원을 고른다. 동점이면 카탈로그 순서상 먼저 오는 것(Python max와 동일).
SoundProfile selectNextSound(
  SoundProfile current,
  List<SoundProfile> catalog,
  List<String> recentlyUsed, {
  bool criticalWakeup = false,
}) {
  final candidates =
      catalog.where((s) => s.soundId != current.soundId).toList();
  if (candidates.isEmpty) return current;

  double score(SoundProfile s) {
    var v = _distance(current.features, s.features); // 다를수록 +
    if (criticalWakeup) {
      v += s.category == 'harsh' ? 2.0 : 0.0; // 확실히 깨우는 힘 우선
    } else {
      v += s.melodyScore; // 멜로디 우선
    }
    if (recentlyUsed.contains(s.soundId)) v -= 1.0; // 최근 사용 후순위
    return v;
  }

  var best = candidates.first;
  var bestScore = score(best);
  for (final s in candidates.skip(1)) {
    final sc = score(s);
    if (sc > bestScore) {
      bestScore = sc;
      best = s;
    }
  }
  return best;
}
