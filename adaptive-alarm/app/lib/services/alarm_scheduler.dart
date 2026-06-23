// OS 정밀 알람 스케줄링 + 알림. (android_alarm_manager_plus + flutter_local_notifications)
//
// ⚠️ 이 레이어는 기기/OS에 깊이 의존하므로 실기기에서 다듬어야 한다(README 한계 참고).
//    - Android: exact alarm + foreground 권한, 풀스크린 인텐트 설정 필요
//    - iOS: android_alarm_manager_plus 미지원. iOS는 별도 구현(로컬 알림 한계) 필요

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AlarmScheduler {
  static const int alarmId = 1001;
  static final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    await AndroidAlarmManager.initialize();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      const InitializationSettings(android: androidInit),
    );
  }

  /// 다음 알람 시각을 정해 예약. 화면이 꺼져 있어도 깨우도록 wakeup+alarmClock.
  static Future<void> scheduleAt(DateTime when) async {
    await AndroidAlarmManager.oneShotAt(
      when,
      alarmId,
      _alarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      alarmClock: true,
      allowWhileIdle: true,
    );
  }

  static Future<void> cancel() async {
    await AndroidAlarmManager.cancel(alarmId);
  }

  /// 매일 같은 시각 알람을 위해 다음 발생 시각을 계산한다.(보고서 2.6: 같은 시각 유도)
  static DateTime nextOccurrence(int hour, int minute, {DateTime? from}) {
    final now = from ?? DateTime.now();
    var t = DateTime(now.year, now.month, now.day, hour, minute);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }
}

/// 별도 isolate에서 실행되는 알람 콜백. UI에 직접 접근 불가.
/// 풀스크린 알림을 띄워 사용자를 깨우고, 탭하면 앱의 RingScreen으로 진입시킨다.
@pragma('vm:entry-point')
void _alarmCallback() async {
  final notif = FlutterLocalNotificationsPlugin();
  const android = AndroidNotificationDetails(
    'alarm_channel',
    '알람',
    channelDescription: '적응형 알람',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    ongoing: true,
    playSound: true,
  );
  await notif.show(
    AlarmScheduler.alarmId,
    '알람',
    '탭하여 끄기',
    const NotificationDetails(android: android),
    payload: 'ring',
  );
  // 실제 음원 재생/스누즈 UI는 앱 진입 후 RingScreen이 담당.
}
