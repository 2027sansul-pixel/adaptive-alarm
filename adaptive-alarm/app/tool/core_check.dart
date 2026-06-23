// 순수 Dart 검증 하니스 (Flutter 불필요). 실행: dart run app/tool/core_check.dart
// test/core_test.dart 와 같은 골든값을 확인하되, package:test 없이 돌도록 한 것.
// core/ 포팅이 Python과 같은 수를 내는지 SDK만으로 검증하는 용도.

import 'dart:convert';
import 'dart:math' as math;

import '../lib/core/config.dart';
import '../lib/core/decision.dart';
import '../lib/core/engine.dart';
import '../lib/core/events.dart';
import '../lib/core/models.dart';
import '../lib/core/scoring.dart';
import '../lib/core/trend.dart';

const _p = kDefaultParams;
int _pass = 0, _fail = 0;

void check(String name, bool cond) {
  if (cond) {
    _pass++;
    print('  ok   $name');
  } else {
    _fail++;
    print('  FAIL $name');
  }
}

void near(String name, double a, double b, [double eps = 1e-9]) =>
    check('$name ($a≈$b)', (a - b).abs() < eps);

AlarmRecord rec(List<double> active,
    {double sleepHours = 7.5, bool isWorkday = true, double phoneDistance = 0.0}) {
  final segs = <AlarmSegment>[];
  var t = 0.0;
  for (var i = 0; i < active.length; i++) {
    final action = i == active.length - 1 ? 'dismiss' : 'snooze';
    segs.add(AlarmSegment(t, t + active[i], action));
    t += active[i] + 540;
  }
  return AlarmRecord(
      dayIndex: 0,
      soundId: 's',
      segments: segs,
      sleepHours: sleepHours,
      isWorkday: isWorkday,
      phoneDistance: phoneDistance);
}

final catalog = const [
  SoundProfile('a', 0.9, [0.6, 0.7, 0.8], 'melodic'),
  SoundProfile('b', 0.8, [0.1, 0.2, 0.1], 'harsh'),
  SoundProfile('c', 0.85, [0.7, 0.5, 0.9], 'melodic'),
];

AlarmRecord escalating(int day, String sound, double active) => buildRecord(
    dayIndex: day,
    soundId: sound,
    interactions: [Interaction(0, active, 'dismiss')],
    sleepHours: 7.5,
    isWorkday: true);

void main() {
  print('[scoring]');
  final r = rec([40, 30, 50]);
  check('활성 시간=120', activeInteractionSeconds(r) == 120);
  check('스누즈=2', snoozeCount(r) == 2);
  near('가산 점수 delta', rawScore(rec([60, 40])) - rawScore(rec([100])),
      _p.snoozeWeight);
  near(
      '교란 보정',
      deconfoundedScore(rec([100], sleepHours: 7.5, isWorkday: false)) -
          deconfoundedScore(rec([100], sleepHours: 5.5, isWorkday: false)),
      _p.sleepDebtCoef * 2.0);
  check('극단 수면부족 true', isExtremeSleepDebt(rec([10], sleepHours: 4.0)));
  check('극단 수면부족 false', !isExtremeSleepDebt(rec([10], sleepHours: 7.0)));

  print('[events]');
  final built = buildRecord(
      dayIndex: 3,
      soundId: 's',
      interactions: const [
        Interaction(0, 40, 'snooze'),
        Interaction(580, 620, 'dismiss')
      ],
      sleepHours: 7.0,
      isWorkday: true);
  check('빌드 활성=80', activeInteractionSeconds(built) == 80);
  var threw = false;
  try {
    buildRecord(
        dayIndex: 0,
        soundId: 's',
        interactions: const [Interaction(0, 40, 'snooze')],
        sleepHours: 7,
        isWorkday: true);
  } catch (_) {
    threw = true;
  }
  check('마지막 dismiss 아니면 throw', threw);

  print('[trend]');
  check('EWMA 간격감쇠', ewmaAlphaForGap(3, _p) > ewmaAlphaForGap(1, _p));
  near('gap1 alpha=lambda', ewmaAlphaForGap(1, _p), _p.lambda);
  final st = TrendState();
  const p20 = Params(lambda: 0.20);
  update(st, 0, 3.6, 0.7, 5.0, p20);
  update(st, 1, 3.6, 0.7, 6.0, p20);
  update(st, 2, 3.6, 0.7, 6.0, p20);
  near('골든 EWMA 5.36', st.ewma!, 5.36);

  print('[engine]');
  final eng = AlarmEngine.create(catalog, 'a');
  int? proposedDay;
  for (var d = 0; d < 60; d++) {
    final active =
        d < _p.baselineDays ? 30.0 : 30.0 + 12.0 * (d - _p.baselineDays);
    final pr = eng.recordAlarm(escalating(d, eng.state.currentSound, active));
    if (pr.propose) {
      proposedDay = d;
      check('제안 from=a', pr.fromSound == 'a');
      check('제안 to 존재', pr.toSound != null);
      break;
    }
  }
  check('상승 추세가 제안을 유발', proposedDay != null);

  final eng2 = AlarmEngine.create(catalog, 'a');
  eng2.acceptSwap('b');
  check('수락 후 현재음원=b', eng2.state.currentSound == 'b');
  check('수락 후 daysOnSound=0', eng2.state.daysOnSound == 0);

  final eng3 = AlarmEngine.create(catalog, 'a');
  for (var d = 0; d < _p.baselineDays; d++) {
    eng3.recordAlarm(escalating(d, 'a', 30));
  }
  eng3.declineSwap();
  check('거절 후 쿨다운', !eng3.recordAlarm(escalating(_p.baselineDays, 'a', 999)).propose);

  final eng4 = AlarmEngine.create(catalog, 'a');
  for (var d = 0; d < 20; d++) {
    eng4.recordAlarm(escalating(d, eng4.state.currentSound, 30.0 + d));
  }
  final restored = AlarmEngine.fromJson(
      catalog, jsonDecode(jsonEncode(eng4.toJson())) as Map<String, dynamic>);
  check('직렬화 왕복 음원', restored.state.currentSound == eng4.state.currentSound);
  check('직렬화 왕복 EWMA', restored.currentTrend().ewma == eng4.currentTrend().ewma);

  print('[golden parity]');
  final g = buildRecord(
      dayIndex: 0,
      soundId: 's',
      interactions: const [
        Interaction(0, 45, 'snooze'),
        Interaction(585, 615, 'snooze'),
        Interaction(1155, 1205, 'dismiss')
      ],
      sleepHours: 6.5,
      isWorkday: true);
  check('골든 활성=125', activeInteractionSeconds(g) == 125);
  final expRaw = math.log(1 + 125) + _p.snoozeWeight * 2;
  near('골든 raw', rawScore(g), expRaw);
  near('골든 deconfound', deconfoundedScore(g),
      expRaw - _p.sleepDebtCoef * 1.0 - _p.workdayCoef);

  print('\n결과: $_pass 통과, $_fail 실패');
}
