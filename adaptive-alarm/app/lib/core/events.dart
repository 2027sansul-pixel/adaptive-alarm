// 원시 알람 상호작용 → AlarmRecord 변환 + 검증. (Python core/events.py 포팅)

import 'models.dart';

/// 한 번의 알람 상호작용.
class Interaction {
  final double ringStartS; // 울리기 시작한 에포크 초
  final double actionS; // 조작한 에포크 초
  final String action; // 'snooze' | 'dismiss'

  const Interaction(this.ringStartS, this.actionS, this.action);
}

/// 월=1 ... 일=7 (Dart DateTime.weekday). 월~금을 근무일로 본다.
/// 주의: Python의 weekday는 월=0이므로, DateTime.weekday를 쓸 땐 이 함수를 쓴다.
bool isWorkdayFromDateTime(int dartWeekday) => dartWeekday <= 5; // 1~5 = 월~금

AlarmRecord buildRecord({
  required int dayIndex,
  required String soundId,
  required List<Interaction> interactions,
  required double sleepHours,
  required bool isWorkday,
  double phoneDistance = 0.0,
  double alarmHour = 7.0,
}) {
  if (interactions.isEmpty) {
    throw ArgumentError('상호작용이 비어 있습니다. 최소 한 번의 해제가 필요합니다.');
  }

  final segments = <AlarmSegment>[];
  double? prevActionS;
  for (final it in interactions) {
    if (it.actionS < it.ringStartS) {
      throw ArgumentError('누른 시각(${it.actionS})이 울린 시각(${it.ringStartS})보다 빠릅니다.');
    }
    if (prevActionS != null && it.ringStartS < prevActionS) {
      throw ArgumentError('구간이 시간순으로 정렬되어 있지 않습니다.');
    }
    if (it.action != 'snooze' && it.action != 'dismiss') {
      throw ArgumentError('알 수 없는 조작 종류: ${it.action}');
    }
    segments.add(AlarmSegment(it.ringStartS, it.actionS, it.action));
    prevActionS = it.actionS;
  }

  if (segments.last.action != 'dismiss') {
    throw ArgumentError("마지막 구간은 반드시 'dismiss'여야 합니다.");
  }
  if (phoneDistance < 0.0 || phoneDistance > 1.0) {
    throw ArgumentError('phoneDistance는 0~1 범위여야 합니다.');
  }

  return AlarmRecord(
    dayIndex: dayIndex,
    soundId: soundId,
    segments: segments,
    sleepHours: sleepHours,
    isWorkday: isWorkday,
    phoneDistance: phoneDistance,
    alarmHour: alarmHour,
  );
}
