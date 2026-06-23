import 'package:flutter/material.dart';

import '../data/sound_catalog.dart';
import '../services/alarm_controller.dart';
import '../services/alarm_scheduler.dart';
import 'ring_screen.dart';

class HomeScreen extends StatefulWidget {
  final AlarmController controller;
  final bool autoRing; // 알람으로 깨어난 경우 즉시 울림 화면으로
  const HomeScreen({super.key, required this.controller, this.autoRing = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late TimeOfDay _time;
  late bool _enabled;

  AlarmController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _time = TimeOfDay(hour: c.storage.alarmHour, minute: c.storage.alarmMinute);
    _enabled = c.storage.enabled;
    if (widget.autoRing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ringNow());
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) {
      setState(() => _time = picked);
      await _applyAlarm();
    }
  }

  Future<void> _applyAlarm() async {
    await c.storage.setAlarm(_time.hour, _time.minute, _enabled);
    if (_enabled) {
      await AlarmScheduler.scheduleAt(
          AlarmScheduler.nextOccurrence(_time.hour, _time.minute));
    } else {
      await AlarmScheduler.cancel();
    }
  }

  Future<void> _ringNow() async {
    // 실기기/실시간 알람을 기다리지 않고 전체 흐름을 테스트하는 디버그 진입점.
    c.onRing(DateTime.now());
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => RingScreen(controller: c)),
    );
    setState(() {}); // 음원이 바뀌었을 수 있으니 갱신
  }

  @override
  Widget build(BuildContext context) {
    final soundLabel = soundAssetById(c.currentSoundId).label;
    final trend = c.engine.currentTrend();
    return Scaffold(
      appBar: AppBar(title: const Text('적응형 알람')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: _pickTime,
                child: Text(_time.format(context),
                    style: const TextStyle(fontSize: 64)),
              ),
            ),
            SwitchListTile(
              title: const Text('알람 켜기'),
              value: _enabled,
              onChanged: (v) async {
                setState(() => _enabled = v);
                await _applyAlarm();
              },
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.music_note),
              title: const Text('현재 알람음'),
              subtitle: Text(soundLabel),
            ),
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('습관화 추세'),
              subtitle: Text(_trendSummary(trend.ewma, c.engine.currentControlLimit())),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: _ringNow,
              icon: const Icon(Icons.alarm_on),
              label: const Text('지금 울리기 (테스트)'),
            ),
          ],
        ),
      ),
    );
  }

  String _trendSummary(double? ewma, double? ucl) {
    if (ewma == null) return '데이터 수집 중';
    final e = ewma.toStringAsFixed(2);
    if (ucl == null) return '기준선 수집 중 (현재 $e)';
    return '현재 $e / 상한선 ${ucl.toStringAsFixed(2)}';
  }
}
