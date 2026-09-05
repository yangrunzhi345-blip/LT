import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/adventure/presentation/session/screens/adventure_session_screen.dart';

@visibleForTesting
bool usesCompactAdventureHeader(Size screenSize) =>
    screenSize.width < 700 || screenSize.shortestSide < 600;

/// 场景冒险主界面（兼容门面，委托至 features/adventure/presentation/session/screens/adventure_session_screen.dart）
class AdventureModeScreen extends ConsumerStatefulWidget {
  final VoidCallback? onMenuPressed;
  final String? initialMessageId;

  const AdventureModeScreen({
    super.key,
    this.onMenuPressed,
    this.initialMessageId,
  });

  @override
  ConsumerState<AdventureModeScreen> createState() =>
      _AdventureModeScreenState();
}

class _AdventureModeScreenState extends ConsumerState<AdventureModeScreen> {
  @override
  Widget build(BuildContext context) {
    return AdventureSessionScreen(
      onMenuPressed: widget.onMenuPressed,
      initialMessageId: widget.initialMessageId,
    );
  }
}
