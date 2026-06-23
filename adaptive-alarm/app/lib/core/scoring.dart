// 원점수 계산과 교란 보정. (Python core/scoring.py 의 포팅)
//
// 활성 상호작용 시간만 신호로 쓰고, 스누즈는 곱하지 않고 더한다.

import 'dart:math' as math;

import 'config.dart';
import 'models.dart';

/// 사용자가 알람과 실제로 씨름한 총 시간(초). 스누즈 대기 구간은 자동 제외.
double activeInteractionSeconds(AlarmRecord r) {
  var sum = 0.0;
  for (final seg in r.segments) {
    sum += seg.actionS - seg.ringStartS;
  }
  return sum;
}

/// 스누즈를 누른 횟수(마지막 해제 구간 제외).
int snoozeCount(AlarmRecord r) =>
    r.segments.where((seg) => seg.action == 'snooze').length;

/// 목표 수면 대비 부족분(시간). 충분히 잤으면 0.
double sleepDebtHours(AlarmRecord r, [Params p = kDefaultParams]) =>
    math.max(0.0, p.targetSleepHours - r.sleepHours);

/// 보정 전 원점수. log(1+활성 시간) + 가중치·스누즈 횟수.
double rawScore(AlarmRecord r, [Params p = kDefaultParams]) =>
    math.log(1.0 + activeInteractionSeconds(r)) + p.snoozeWeight * snoozeCount(r);

/// 원점수에서 수면 부채·요일·휴대폰 거리의 영향을 빼낸 값. 추세·판정의 입력.
double deconfoundedScore(AlarmRecord r, [Params p = kDefaultParams]) {
  var score = rawScore(r, p);
  score -= p.sleepDebtCoef * sleepDebtHours(r, p);
  score -= p.workdayCoef * (r.isWorkday ? 1.0 : 0.0);
  score -= p.phoneDistCoef * r.phoneDistance;
  return score;
}

/// 교체 판정에서 제외할 만큼 극단적으로 잠이 부족했는가.
bool isExtremeSleepDebt(AlarmRecord r, [Params p = kDefaultParams]) =>
    sleepDebtHours(r, p) >= p.extremeDebtHours;
