// core/ Dart 포팅의 단위 + 골든(parity) 테스트.  실행: flutter test
//
// 골든 값은 Python tests/test_core.py 와 동일하다. 양쪽이 같은 입력에 같은 수를
// 내는지가 포팅 정확성의 기준이다.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:adaptive_alarm/core/config.dart';
import 'package:adaptive_alarm/core/decision.dart';
import 'package:adaptive_alarm/core/engine.dart';
import 'package:adaptive_alarm/core/events.dart';
import 'package:adaptive_alarm/core/models.dart';
import 'package:adaptive_alarm/core/scoring.dart';
import 'package:adaptive_alarm/core/trend.dart';

const _p = kDefaultParams;

// 활성 시간 목록으로 AlarmRecord 만들기(스누즈 대기는 큰 간격으로).
AlarmRecord _rec(List<double> active,
    {double sleepHours = 7.5, bool isWorkday = true, double phoneDistance = 0.0}) {
  final segs = <AlarmSegment>[];
  var t = 0.0;
  for (var i = 0; i < active.length; i++) {
    final action = i == active.length - 1 ? 'dismiss' : 'snooze';
    segs.add(AlarmSegment(t, t + active[i], action));
    t += active[i] + 540; // 9분 스누즈 대기
  }
  return AlarmRecord(
    dayIndex: 0,
    soundId: 's',
    segments: segs,
    sleepHours: sleepHours,
    isWorkday: isWorkday,
    phoneDistance: phoneDistance,
  );
}

final _catalog = [
  const SoundProfile('a', 0.9, [0.6, 0.7, 0.8], 'melodic'),
  const SoundProfile('b', 0.8, [0.1, 0.2, 0.1], 'harsh'),
  const SoundProfile('c', 0.85, [0.7, 0.5, 0.9], 'melodic'),
];

AlarmRecord _escalating(int day, String sound, double active) => buildRecord(
      dayIndex: day,
      soundId: sound,
      interactions: [Interaction(0, active, 'dismiss')],
      sleepHours: 7.5,
      isWorkday: true,
    );

void main() {
  group('scoring', () {
    test('활성 시간은 스누즈 대기를 제외한다', () {
      final rec = _rec([40, 30, 50]);
      expect(activeInteractionSeconds(rec), 120);
      expect(snoozeCount(rec), 2);
    });

    test('원점수는 가산(곱셈 아님)', () {
      final a = _rec([100]);
      final b = _rec([60, 40]); // 활성 동일, 스누즈 1
      expect(rawScore(b) - rawScore(a), closeTo(_p.snoozeWeight, 1e-9));
    });

    test('교란 보정이 요인을 뺀다', () {
      final base = _rec([100], sleepHours: 7.5, isWorkday: false);
      final debt = _rec([100], sleepHours: 5.5, isWorkday: false);
      expect(deconfoundedScore(base) - deconfoundedScore(debt),
          closeTo(_p.sleepDebtCoef * 2.0, 1e-9));
    });

    test('극단적 수면 부족 플래그', () {
      expect(isExtremeSleepDebt(_rec([10], sleepHours: 4.0)), isTrue);
      expect(isExtremeSleepDebt(_rec([10], sleepHours: 7.0)), isFalse);
    });
  });

  group('events', () {
    test('빌드 + 검증', () {
      final rec = buildRecord(
        dayIndex: 3,
        soundId: 's',
        interactions: [
          const Interaction(0, 40, 'snooze'),
          const Interaction(580, 620, 'dismiss'),
        ],
        sleepHours: 7.0,
        isWorkday: true,
      );
      expect(activeInteractionSeconds(rec), 80); // 40 + 40
    });

    test('마지막이 dismiss 아니면 거부', () {
      expect(
        () => buildRecord(
          dayIndex: 0,
          soundId: 's',
          interactions: [const Interaction(0, 40, 'snooze')],
          sleepHours: 7.0,
          isWorkday: true,
        ),
        throwsArgumentError,
      );
    });
  });

  group('trend', () {
    test('EWMA 간격 감쇠', () {
      final a1 = ewmaAlphaForGap(1, _p);
      final a3 = ewmaAlphaForGap(3, _p);
      expect(a1, closeTo(_p.lambda, 1e-9));
      expect(a3, greaterThan(a1));
    });

    test('기준선은 N일 후 확정', () {
      final st = resetForNewSound();
      for (var d = 0; d < _p.baselineDays; d++) {
        update(st, d, 3.6, 0.7, 4.0, _p);
      }
      expect(st.baselineReady, isTrue);
      expect(controlLimit(st, _p), isNotNull);
    });

    // 골든: λ=0.20, 5.0 → 5.2 → 5.36
    test('알려진 EWMA 시퀀스', () {
      const p = Params(lambda: 0.20);
      final st = TrendState();
      update(st, 0, 3.6, 0.7, 5.0, p);
      update(st, 1, 3.6, 0.7, 6.0, p);
      update(st, 2, 3.6, 0.7, 6.0, p);
      expect(st.ewma, closeTo(5.36, 1e-9));
    });
  });

  group('engine', () {
    test('상승 추세는 교체를 제안한다', () {
      final eng = AlarmEngine.create(_catalog, 'a');
      int? proposedDay;
      for (var d = 0; d < 60; d++) {
        final active = d < _p.baselineDays
            ? 30.0
            : 30.0 + 12.0 * (d - _p.baselineDays);
        final p = eng.recordAlarm(_escalating(d, eng.state.currentSound, active));
        if (p.propose) {
          proposedDay = d;
          expect(p.fromSound, 'a');
          expect(p.toSound, isNotNull);
          break;
        }
      }
      expect(proposedDay, isNotNull);
    });

    test('수락은 리셋하고 전환한다', () {
      final eng = AlarmEngine.create(_catalog, 'a');
      eng.acceptSwap('b');
      expect(eng.state.currentSound, 'b');
      expect(eng.state.daysOnSound, 0);
      expect(eng.state.daysSinceSwap, 0);
      expect(eng.state.recentlyUsed.contains('b'), isTrue);
    });

    test('거절은 쿨다운을 시작한다', () {
      final eng = AlarmEngine.create(_catalog, 'a');
      for (var d = 0; d < _p.baselineDays; d++) {
        eng.recordAlarm(_escalating(d, 'a', 30));
      }
      eng.declineSwap();
      expect(eng.state.daysSinceDecline, 0);
      final p = eng.recordAlarm(_escalating(_p.baselineDays, 'a', 999));
      expect(p.propose, isFalse); // 쿨다운 중
    });

    test('직렬화 왕복', () {
      final eng = AlarmEngine.create(_catalog, 'a');
      for (var d = 0; d < 20; d++) {
        eng.recordAlarm(_escalating(d, eng.state.currentSound, 30.0 + d));
      }
      final data = jsonDecode(jsonEncode(eng.toJson())) as Map<String, dynamic>;
      final restored = AlarmEngine.fromJson(_catalog, data);
      expect(restored.state.currentSound, eng.state.currentSound);
      expect(restored.state.daysOnSound, eng.state.daysOnSound);
      expect(restored.currentTrend().ewma, eng.currentTrend().ewma);
    });
  });

  group('golden parity', () {
    test('알려진 활성 시간과 점수', () {
      final rec = buildRecord(
        dayIndex: 0,
        soundId: 's',
        interactions: [
          const Interaction(0, 45, 'snooze'),
          const Interaction(585, 615, 'snooze'),
          const Interaction(1155, 1205, 'dismiss'),
        ],
        sleepHours: 6.5,
        isWorkday: true,
      );
      expect(activeInteractionSeconds(rec), 125); // 45+30+50
      expect(snoozeCount(rec), 2);
      // deconfound: -0.08*1.0(수면부채1h) -0.10(근무일)
      final expectedRaw = math.log(1 + 125) + _p.snoozeWeight * 2;
      expect(rawScore(rec), closeTo(expectedRaw, 1e-9));
      final expectedDec =
          expectedRaw - _p.sleepDebtCoef * 1.0 - _p.workdayCoef;
      expect(deconfoundedScore(rec), closeTo(expectedDec, 1e-9));
    });
  });
}
