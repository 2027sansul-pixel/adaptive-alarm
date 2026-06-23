// OS 정밀 알람 스케줄링 + 알림. (android_alarm_manager_plus + flutter_local_notifications)
//
// ⚠️ 이 레이어는 기기/OS에 깊이 의존하므로 실기기에서 다듬어야 한다(SETUP.md 참고).
//    - Android: exact alarm + 풀스크린 인텐트 권한, 알림 채널 설정 필요
//    - iOS: android_alarm_manager_plus 미지원. iOS는 별도 구현(로컬 알림 한계) 필요

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AlarmScheduler {
  static const int alarmId = 1001;
  static const String _channelId = 'alarm_channel';
  static final FlutterLocalNotificationsPlugin _notif =
      FlutterLocalNotificationsPlugin();

  /// 앱이 알람으로 깨어나야 할 때 호출되는 콜백. main에서 RingScreen 진입을 연결한다.
  static void Function()? onRingRequested;

  static Future<void> init() async {
    await AndroidAlarmManager.initialize();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notif.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: (resp) {
        if (resp.payload == 'ring') onRingRequested?.call();
      },
    );
  }

  /// 앱이 알람 알림을 탭해서 시작됐는지. main()에서 초기 화면을 정하는 데 쓴다.
  static Future<bool> launchedFromAlarm() async {
    final details = await _notif.getNotificationAppLaunchDetails();
    return (details?.didNotificationLaunchApp ?? false) &&
        details?.notificationResponse?.payload == 'ring';
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
/// 풀스크린 알림을 띄워 사용자를 깨우고, 탭/풀스크린 진입으로 앱이 RingScreen에 들어간다.
@pragma('vm:entry-point')
void _alarmCallback() async {
  final notif = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await notif.initialize(const InitializationSettings(android: androidInit));

  const android = AndroidNotificationDetails(
    AlarmScheduler._channelId,
    '알람',
    channelDescription: '적응형 알람',
    importance: Importance.max,
    priority: Priority.high,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.alarm,
    ongoing: true,
    playSound: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );
  await notif.show(
    AlarmScheduler.alarmId,
    '알람',
    '탭하여 끄기',
    const NotificationDetails(android: android),
    payload: 'ring',
  );
}
