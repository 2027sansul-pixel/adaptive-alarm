import 'package:flutter/material.dart';

import 'services/alarm_controller.dart';
import 'services/alarm_scheduler.dart';
import 'ui/home_screen.dart';
import 'ui/ring_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  late final AlarmController controller;

  // 알람 알림을 탭했을 때(앱이 떠 있는 동안) RingScreen으로 진입시키는 연결.
  AlarmScheduler.onRingRequested = () {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    controller.onRing(DateTime.now());
    Navigator.of(ctx).push(
      MaterialPageRoute(builder: (_) => RingScreen(controller: controller)),
    );
  };

  await AlarmScheduler.init();
  controller = await AlarmController.init();

  // 잠금화면 풀스크린 인텐트로 앱이 깨어난 경우 곧장 울림 화면으로.
  final autoRing = await AlarmScheduler.launchedFromAlarm();

  runApp(AdaptiveAlarmApp(controller: controller, autoRing: autoRing));
}

class AdaptiveAlarmApp extends StatelessWidget {
  final AlarmController controller;
  final bool autoRing;
  const AdaptiveAlarmApp({
    super.key,
    required this.controller,
    this.autoRing = false,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '적응형 알람',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(controller: controller, autoRing: autoRing),
    );
  }
}
