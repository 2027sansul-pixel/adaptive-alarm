// 자료구조. (Python core/models.py 의 포팅)

/// 알람이 한 번 울린 구간. 스누즈를 N번 누르면 N+1개의 구간이 생긴다.
/// ringStartS ~ actionS 사이만 '실제로 씨름한 시간'이며, 스누즈 대기 시간은
/// 구간 사이 빈 공간으로 남아 어떤 활성 시간에도 포함되지 않는다.
class AlarmSegment {
  final double ringStartS; // 이 구간에서 알람이 울리기 시작한 시각(에포크 초)
  final double actionS; // 사용자가 조작(스누즈/해제)한 시각
  final String action; // 'snooze' | 'dismiss'

  const AlarmSegment(this.ringStartS, this.actionS, this.action);
}

/// 하루 한 번의 기상에 대한 전체 기록.
class AlarmRecord {
  final int dayIndex; // 0부터 시작하는 일자 인덱스(달력 간격 계산용)
  final String soundId;
  final List<AlarmSegment> segments;
  final double sleepHours; // 전날 대략 수면 시간
  final bool isWorkday;
  final double phoneDistance; // 0~1, 멀수록 1
  final double alarmHour;

  const AlarmRecord({
    required this.dayIndex,
    required this.soundId,
    required this.segments,
    this.sleepHours = 7.0,
    this.isWorkday = true,
    this.phoneDistance = 0.0,
    this.alarmHour = 7.0,
  });
}

/// 알람음 한 종류의 음향 메타데이터.
class SoundProfile {
  final String soundId;
  final double melodyScore; // 0~1, 멜로디에 가까울수록 1
  final List<double> features; // 템포·음높이·밝기 등 정규화 특징 벡터
  final String category; // 'melodic' | 'beep' | 'harsh'

  const SoundProfile(this.soundId, this.melodyScore, this.features, this.category);
}
