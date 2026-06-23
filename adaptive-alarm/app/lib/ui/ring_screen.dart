import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../data/sound_catalog.dart';
import '../services/alarm_controller.dart';
import 'swap_proposal_sheet.dart';

/// 알람이 울리는 화면. 스누즈/해제 버튼. 해제 시 기록을 처리하고 필요하면 교체 제안.
class RingScreen extends StatefulWidget {
  final AlarmController controller;
  const RingScreen({super.key, required this.controller});

  @override
  State<RingScreen> createState() => _RingScreenState();
}

class _RingScreenState extends State<RingScreen> {
  final _player = AudioPlayer();
  AlarmController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _playCurrentSound();
  }

  Future<void> _playCurrentSound() async {
    final asset = soundAssetById(c.currentSoundId);
    await _player.setReleaseMode(ReleaseMode.loop);
    // 자산 경로는 audioplayers의 AssetSource 규칙(assets/ 접두 제외)에 맞춰 다듬어야 함.
    await _player.play(AssetSource(asset.assetPath.replaceFirst('assets/', '')));
  }

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  void _snooze() {
    c.onSnooze(DateTime.now());
    // 실제로는 N분 뒤 다시 울리도록 스케줄하고 화면을 닫는다.
    // 테스트 편의상 여기서는 다시 울림으로 처리.
    c.onRing(DateTime.now());
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('스누즈')));
  }

  Future<void> _dismiss() async {
    await _player.stop();
    // TODO: 전날 수면 시간은 MVP에서 정밀 추정 없음. 기본값 사용(보고서 2.1).
    final proposal = await c.onDismiss(DateTime.now(), sleepHours: 7.5);
    if (!mounted) return;

    if (proposal.propose && proposal.toSound != null) {
      await showSwapProposalSheet(context, c, proposal);
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.alarm, size: 96),
            const SizedBox(height: 16),
            Text(TimeOfDay.now().format(context),
                style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 64),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _snooze,
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20)),
                      child: const Text('스누즈'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _dismiss,
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 20)),
                      child: const Text('끄기'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
