import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../../providers/riverpod_providers.dart';
import '../../../providers/chat_provider.dart';
import '../../../models/adventure_response.dart';
import '../../../models/message.dart';
import '../../../core/router/app_router.dart';
import '../../../features/adventure/presentation/session/screens/model_select_page.dart';
import '../../../features/adventure/presentation/session/screens/message_edit_page.dart';
import 'inventory_screen.dart';

/// 复制消息的可见文本：双段响应（叙事 + ---JSON---）只复制叙事部分，
/// 与气泡实际展示内容一致。
Future<void> copyMessageDisplayText(
    BuildContext context, dynamic message) async {
  final raw = message.content as String;
  final display = AdventureResponse.streamingDisplayText(raw).trim();
  await Clipboard.setData(ClipboardData(text: display.isEmpty ? raw : display));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('已复制到剪贴板')),
  );
}

Future<bool> regenerateMessage(Message message, ChatProvider provider) async {
  final idx = provider.messages.indexOf(message);
  if (idx < 0) {
    debugPrint(
        '[regenerateMessage] indexOf returned -1 for message.id=${message.id}');
    return false;
  }

  // 找到要重新发送的用户消息内容，以及要清理旧回复的位置
  String? userContent;
  if (message.isUser) {
    userContent = message.content;
  } else {
    // AI 消息：找到前一条用户消息，从当前 AI 消息开始删除，保留之前的用户消息。
    for (int i = idx - 1; i >= 0; i--) {
      if (provider.messages[i].isUser) {
        userContent = provider.messages[i].content;
        break;
      }
    }
  }

  if (userContent == null || userContent.trim().isEmpty) return false;

  // 先同步截断 SQLite 与内存，再开始新请求，避免重开会话后旧回复复活。
  final content = userContent;
  if (!await provider.prepareMessageRegeneration(idx)) return false;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    provider.sendMessage(content);
  });
  return true;
}

bool canRegenerateMessage(Message message, ChatProvider provider) {
  final index = provider.messages.indexOf(message);
  if (index < 0) return false;
  if (message.isUser) return message.content.trim().isNotEmpty;
  for (int i = index - 1; i >= 0; i--) {
    final candidate = provider.messages[i];
    if (candidate.isUser) return candidate.content.trim().isNotEmpty;
  }
  return false;
}

void showEditDialog(
    BuildContext context, Message message, ChatProvider provider) {
  AppRouter.push<bool>(
    context,
    pageBuilder: (_) => MessageEditPage(message: message),
  );
}

void showRegenerateWithModelMenu(
    BuildContext context, Message message, ChatProvider provider) {
  AppRouter.push<ModelSelectionResult>(
    context,
    pageBuilder: (_) => ModelSelectPage(
      isRegenerate: true,
      message: message,
    ),
  );
}

void showMessageMenu(BuildContext context, message, ChatProvider provider) {
  final isUser = message.isUser;
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2)),
          ),
          // 用户消息的修改已由气泡下方可见按钮承担，仅 AI 回复保留菜单编辑
          if (!isUser)
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑消息'),
              onTap: () {
                Navigator.pop(ctx);
                showEditDialog(context, message, provider);
              },
            ),
          if (!isUser)
            ListTile(
              leading: const Icon(Icons.volume_up),
              title: const Text('朗读'),
              onTap: () {
                Navigator.pop(ctx);
                provider.settingsProvider.tts.speak(message.content);
              },
            ),
          if (!isUser &&
              message.reasoningContent != null &&
              (message.reasoningContent as String).trim().isNotEmpty)
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('复制思考过程 (思维链)'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(
                    ClipboardData(text: message.reasoningContent as String));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('思维链已复制到剪贴板')),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('用其他模型重试'),
            onTap: () {
              Navigator.pop(ctx);
              showRegenerateWithModelMenu(context, message, provider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.call_split),
            title: const Text('从此处分叉'),
            onTap: () {
              Navigator.pop(ctx);
              final idx = provider.messages.indexOf(message);
              if (idx >= 0) {
                provider.forkAdventure(idx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已创建分支 ${provider.currentBranchId}')),
                );
              }
            },
          ),
          if (!isUser)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                provider.deleteMessage(message);
              },
            ),
        ],
      ),
    ),
  );
}

void showRetryMenu(BuildContext context) {
  AppRouter.push<ModelSelectionResult>(
    context,
    pageBuilder: (_) => const ModelSelectPage(),
  );
}

void showModelSwitchMenu(BuildContext context) {
  AppRouter.push<ModelSelectionResult>(
    context,
    pageBuilder: (_) => const ModelSelectPage(),
  );
}

void showInventorySheet(
    BuildContext context, List<String> inventory, bool isDark) {
  final provider =
      ProviderScope.containerOf(context, listen: false).read(chatProvider);
  AppRouter.push<void>(
    context,
    pageBuilder: (_) => InventoryScreen(
      adventureId: provider.currentAdventureId,
      legacyInventory: inventory,
    ),
  );
}
