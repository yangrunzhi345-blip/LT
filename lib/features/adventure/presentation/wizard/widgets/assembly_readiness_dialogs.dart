import 'package:flutter/material.dart';

/// Phase 10 readiness 反馈对话框。
///
/// - [showAssemblyReadinessBlockDialog]：准备中 / 准备失败 / 尚无可用版本时，
///   用可理解的中文说明阻止启动原因。
/// - [showStaleAssemblyChoiceDialog]：存在旧 ready revision 且资源已修改时，
///   让用户**明确选择**是否使用上一个已就绪版本，绝不静默降级。

/// 阻断类反馈（准备中 / 失败 / 尚无可用版本）。
Future<void> showAssemblyReadinessBlockDialog(
  BuildContext context,
  List<String> messages,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('暂时无法开始冒险'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final message in messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(message),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// 旧版本明确选择：返回 true 表示用户选择「使用上一个已就绪版本」。
Future<bool> showStaleAssemblyChoiceDialog(
  BuildContext context,
  List<String> messages,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('资源已修改'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('以下资源在最近一次就绪后又发生了修改：'),
              ),
              for (final message in messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(message),
                ),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('是否使用上一个已就绪版本开始冒险？'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('使用上一个已就绪版本'),
        ),
      ],
    ),
  );
  return result == true;
}
