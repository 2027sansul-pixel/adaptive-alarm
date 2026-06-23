// AlarmEngine: 시스템 핵심 facade. (Python core/engine.py 포팅)
//
// JSON 키는 Python 쪽과 동일한 snake_case를 써서 양쪽 저장 데이터가 호환된다.

import 'config.dart';
import 'decision.dart';
import 'models.dart';
import 'scoring.dart';
import 'trend.dart';

/// 데이터 없는 음원 콜드스타트용 모집단 기준선 기본값 [평균, 표준편차].
const List<double> kDefaultPrior = [3.6, 0.7];

const int _big = 10000;

class SwapProposal {
  final bool propose;
  final String fromSound;
  final String? toSound;
  final String reason;

  const SwapProposal(this.propose, this.fromSound,
      {this.toSound, this.reason = ''});
}

/// 직렬화되는 사용자별 진행 상태.
class EngineState {
  String currentSound;
  int daysOnSound;
  int daysSinceSwap;
  int daysSinceDecline;
  List<String> recentlyUsed;
  Map<String, TrendState> trends;

  EngineState({
    required this.currentSound,
    this.daysOnSound = 0,
    this.daysSinceSwap = _big,
    this.daysSinceDecline = _big,
    List<String>? recentlyUsed,
    Map<String, TrendState>? trends,
  })  : recentlyUsed = recentlyUsed ?? <String>[],
        trends = trends ?? <String, TrendState>{};
}

class AlarmEngine {
  final List<SoundProfile> catalogList;
  final Map<String, SoundProfile> catalog;
  final Params params;
  final Map<String, List<double>> priors;
  final EngineState state;

  AlarmEngine(
    this.catalogList,
    this.state, {
    this.params = kDefaultParams,
    Map<String, List<double>>? priors,
  })  : catalog = {for (final s in catalogList) s.soundId: s},
        priors = priors ?? <String, List<double>>{} {
    if (!catalog.containsKey(state.currentSound)) {
      throw ArgumentError('카탈로그에 없는 음원: ${state.currentSound}');
    }
  }

  /// 새 사용자용 엔진.
  factory AlarmEngine.create(
    List<SoundProfile> catalog,
    String startSound, {
    Params params = kDefaultParams,
    Map<String, List<double>>? priors,
  }) {
    final st = EngineState(currentSound: startSound, recentlyUsed: [startSound]);
    return AlarmEngine(catalog, st, params: params, priors: priors);
  }

  /// 오늘의 알람 기록을 받아 추세를 갱신하고 교체 제안 여부를 돌려준다.
  SwapProposal recordAlarm(AlarmRecord record) {
    final sound = state.currentSound;
    final trend = state.trends.putIfAbsent(sound, resetForNewSound);

    final prior = priors[sound] ?? kDefaultPrior;
    final score = deconfoundedScore(record, params);
    update(trend, record.dayIndex, prior[0], prior[1], score, params);

    final proposal = _decide(record);

    // 하루가 지났으므로 카운터 진행(수락/거절은 별도 호출에서 리셋).
    state.daysOnSound += 1;
    state.daysSinceSwap += 1;
    state.daysSinceDecline += 1;
    return proposal;
  }

  SwapProposal _decide(AlarmRecord record) {
    final trend = state.trends[state.currentSound]!;

    if (state.daysSinceDecline < params.proposalSnoozeDays) {
      return SwapProposal(false, state.currentSound, reason: '거절 쿨다운 중');
    }

    if (!shouldProposeSwap(
      trend,
      record,
      daysOnCurrentSound: state.daysOnSound,
      daysSinceLastSwap: state.daysSinceSwap,
      params: params,
    )) {
      return SwapProposal(false, state.currentSound);
    }

    final nxt = selectNextSound(
        catalog[state.currentSound]!, catalogList, state.recentlyUsed);
    return SwapProposal(true, state.currentSound,
        toSound: nxt.soundId, reason: '추세가 관리 상한선을 넘고 연속 초과 조건을 만족함');
  }

  /// 사용자가 교체 수락. 새 음원으로 바꾸고 추세를 처음부터 다시 모은다.
  void acceptSwap(String toSound) {
    if (!catalog.containsKey(toSound)) {
      throw ArgumentError('카탈로그에 없는 음원: $toSound');
    }
    state.currentSound = toSound;
    final ru = [...state.recentlyUsed, toSound];
    state.recentlyUsed = ru.length > 3 ? ru.sublist(ru.length - 3) : ru;
    state.daysOnSound = 0;
    state.daysSinceSwap = 0;
    state.daysSinceDecline = _big;
    state.trends[toSound] = resetForNewSound();
  }

  /// 사용자가 제안 거절. 쿨다운 시작.
  void declineSwap() {
    state.daysSinceDecline = 0;
  }

  TrendState currentTrend() =>
      state.trends.putIfAbsent(state.currentSound, resetForNewSound);

  double? currentControlLimit() => controlLimit(currentTrend(), params);

  // ---- 직렬화 (Python to_dict/from_dict 와 동일 키) ----
  Map<String, dynamic> toJson() => {
        'current_sound': state.currentSound,
        'days_on_sound': state.daysOnSound,
        'days_since_swap': state.daysSinceSwap,
        'days_since_decline': state.daysSinceDecline,
        'recently_used': state.recentlyUsed,
        'trends': {
          for (final e in state.trends.entries) e.key: _trendToJson(e.value)
        },
      };

  factory AlarmEngine.fromJson(
    List<SoundProfile> catalog,
    Map<String, dynamic> data, {
    Params params = kDefaultParams,
    Map<String, List<double>>? priors,
  }) {
    final trends = <String, TrendState>{};
    (data['trends'] as Map<String, dynamic>).forEach((k, v) {
      trends[k] = _trendFromJson(v as Map<String, dynamic>);
    });
    final st = EngineState(
      currentSound: data['current_sound'] as String,
      daysOnSound: data['days_on_sound'] as int,
      daysSinceSwap: data['days_since_swap'] as int,
      daysSinceDecline: data['days_since_decline'] as int,
      recentlyUsed: (data['recently_used'] as List).cast<String>(),
      trends: trends,
    );
    return AlarmEngine(catalog, st, params: params, priors: priors);
  }
}

Map<String, dynamic> _trendToJson(TrendState t) => {
      'ewma': t.ewma,
      'last_day_index': t.lastDayIndex,
      'baseline_scores': t.baselineScores,
      'baseline_mean': t.baselineMean,
      'baseline_sigma': t.baselineSigma,
      'recent_above': t.recentAbove,
    };

TrendState _trendFromJson(Map<String, dynamic> d) => TrendState(
      ewma: (d['ewma'] as num?)?.toDouble(),
      lastDayIndex: d['last_day_index'] as int?,
      baselineScores:
          (d['baseline_scores'] as List).map((e) => (e as num).toDouble()).toList(),
      baselineMean: (d['baseline_mean'] as num?)?.toDouble(),
      baselineSigma: (d['baseline_sigma'] as num?)?.toDouble(),
      recentAbove: (d['recent_above'] as List).cast<bool>(),
    );
