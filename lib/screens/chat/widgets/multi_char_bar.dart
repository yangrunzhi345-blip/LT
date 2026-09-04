import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../../providers/riverpod_providers.dart';
import '../../../core/theme/app_colors.dart';

class MultiCharacterBar extends StatelessWidget {
  const MultiCharacterBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (_, ref, __) {
        final p = ref.watch(chatProvider);
        if (!p.multiCharacterMode || p.currentCharacterSpeaker == null) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: AppColors.accent.withValues(alpha: 0.1),
          child: Row(children: [
            const Icon(Icons.people, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text('当前发言：${p.currentCharacterSpeaker}',
                style: const TextStyle(fontSize: 11, color: AppColors.accent)),
            const Spacer(),
            Text('轮 ${p.currentCharacterRound + 1}',
                style: TextStyle(fontSize: 10, color: Colors.grey[500])),
          ]),
        );
      },
    );
  }
}
