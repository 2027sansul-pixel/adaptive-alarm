// 알람 세션 ↔ 엔진 ↔ 저장소를 잇는 컨트롤러. UI는 이것만 다루면 된다.
//
// 한 번의 기상 동안: onRing(울림) → onSnooze(여러 번) → onDismiss(완전 해제).
// onDismiss에서 활성 상호작용 기록을 만들어 엔진에 넣고 결과(제안)를 돌려준다.

import '../core/engine.dart';
import '../core/events.dart';
import 'storage.dart';

class AlarmController {
  final AppStorage storage;
  AlarmEngine engine;

  // 진행 중인 세션 상태
  final List<Interaction> _interactions = [];
  double? _currentRingStartS;

  AlarmController(this.storage, this.engine);

  static Future<AlarmController> init() async {
    final s = await AppStorage.open();
    return AlarmController(s, s.loadEngine());
  }

  String get currentSoundId => engine.state.currentSound;

  double _epoch(DateTime t) => t.millisecondsSinceEpoch / 1000.0;

  /// 알람이 (다시) 울리기 시작.
  void onRing(DateTime now) {
    _currentRingStartS = _epoch(now);
  }

  /// 스누즈를 눌렀다. 이번 구간의 활성 시간이 확정된다(대기 시간은 포함 안 됨).
  void onSnooze(DateTime now) {
    final start = _currentRingStartS;
    if (start == null) return;
    _interactions.add(Interaction(start, _epoch(now), 'snooze'));
    _currentRingStartS = null;
  }

  /// 완전히 껐다. 기록을 만들어 엔진에 넣고 교체 제안 여부를 돌려준다.
  Future<SwapProposal> onDismiss(
    DateTime now, {
    required double sleepHours,
    double phoneDistance = 0.0,
  }) async {
    final start = _currentRingStartS;
    if (start != null) {
      _interactions.add(Interaction(start, _epoch(now), 'dismiss'));
      _currentRingStartS = null;
    }

    final record = buildRecord(
      dayIndex: storage.currentDayIndex(now),
      soundId: engine.state.currentSound,
      interactions: List.of(_interactions),
      sleepHours: sleepHours,
      isWorkday: isWorkdayFromDateTime(now.weekday),
      phoneDistance: phoneDistance,
      alarmHour: now.hour.toDouble(),
    );

    final proposal = engine.recordAlarm(record);
    await storage.saveEngine(engine);
    _interactions.clear();
    return proposal;
  }

  Future<void> acceptSwap(String toSound) async {
    engine.acceptSwap(toSound);
    await storage.saveEngine(engine);
  }

  Future<void> declineSwap() async {
    engine.declineSwap();
    await storage.saveEngine(engine);
  }
}
