import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../data/sound_catalog.dart';
import '../services/alarm_controller.dart';

/// 교체 제안 시트. 강제로 바꾸지 않고 사용자가 선택한다.(보고서 2.4)
///   - 지금 바꾸기 / 이 음원 계속 쓰기(거절)
Future<void> showSwapProposalSheet(
  BuildContext context,
  AlarmController controller,
  SwapProposal proposal,
) {
  final fromLabel = soundAssetById(proposal.fromSound).label;
  final toLabel = soundAssetById(proposal.toSound!).label;

  return showModalBottomSheet(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.autorenew, size: 40),
          const SizedBox(height: 16),
          Text('알람음을 바꿔볼까요?',
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '$fromLabel 에 익숙해진 것 같아요.\n$toLabel 로 바꾸면 더 잘 깰 수 있어요.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              await controller.acceptSwap(proposal.toSound!);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('$toLabel 로 바꾸기'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              await controller.declineSwap();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('계속 이 음원 쓰기'),
          ),
        ],
      ),
    ),
  );
}
