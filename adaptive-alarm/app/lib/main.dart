import 'package:flutter/material.dart';

import 'services/alarm_controller.dart';
import 'services/alarm_scheduler.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlarmScheduler.init();
  final controller = await AlarmController.init();
  runApp(AdaptiveAlarmApp(controller: controller));
}

class AdaptiveAlarmApp extends StatelessWidget {
  final AlarmController controller;
  const AdaptiveAlarmApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '적응형 알람',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: HomeScreen(controller: controller),
    );
  }
}
