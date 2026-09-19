import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../../providers/riverpod_providers.dart';
import '../../../providers/chat_provider.dart';
import '../../../models/llm_provider.dart';
import '../../../models/adventure_response.dart';
import '../../../models/message.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
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

void regenerateMessage(Message message, ChatProvider provider) {
  final idx = provider.messages.indexOf(message);
  if (idx < 0) {
    debugPrint(
        '[regenerateMessage] indexOf returned -1 for message.id=${message.id}');
    return;
  }

  // 找到要重新发送的用户消息内容，以及要清理旧回复的位置
  String? userContent;
  int? deleteFrom; // 从哪个位置开始删除旧回复（包含该位置）
  if (message.isUser) {
    userContent = message.content;
    deleteFrom = idx + 1; // 仅删除该用户消息之后的回复，保留该用户消息自身
  } else {
    // AI 消息：找到前一条用户消息，从当前 AI 消息开始删除，保留之前的用户消息
    for (int i = idx - 1; i >= 0; i--) {
      if (provider.messages[i].isUser) {
        userContent = provider.messages[i].content;
        deleteFrom = idx; // 从当前 AI 消息开始删，保留用户消息自身
        break;
      }
    }
  }

  if (userContent == null || deleteFrom == null) return;
  if (userContent.trim().isEmpty) return;

  // 原地覆盖重发：删除从 deleteFrom 开始的旧回复，用户消息原地保留
  final content = userContent;
  provider.deleteMessagesAfter(deleteFrom);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    provider.sendMessage(content);
  });
}

bool editMessage(Message message, String newContent, ChatProvider provider) {
  if (newContent.isEmpty || newContent == message.content) return false;

  final idx = provider.messages.indexOf(message);
  if (idx < 0) {
    debugPrint(
        '[editMessage] indexOf returned -1 for message.id=${message.id}');
    return false;
  }

  if (message.isUser) {
    // 原地替换编辑后的消息
    provider.messages[idx] =
        message.copyWith(content: newContent, isEdited: true);
    // 删除该消息之后的所有旧回复
    provider.deleteMessagesAfter(idx + 1);
    // sendMessage 会自动检测末尾已有的用户消息并原地复用
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.sendMessage(newContent);
    });
  } else {
    provider.messages[idx] = message.copyWith(content: newContent);
    provider.triggerRebuild();
  }
  return true;
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
  final provider =
      ProviderScope.containerOf(context, listen: false).read(chatProvider);
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
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.swap_horiz, size: 20, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text('选择模型重试',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ...LLMProvider.values.map((p) => ListTile(
                leading: Icon(Icons.cloud_outlined,
                    color:
                        p == provider.providerType ? AppColors.accent : null),
                title: Text(p.displayName),
                subtitle:
                    Text(p.defaultModel, style: const TextStyle(fontSize: 12)),
                trailing: p == provider.providerType
                    ? const Icon(Icons.check_circle,
                        size: 20, color: AppColors.accent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  provider.retryLast(
                      overrideProvider: p, overrideModel: p.defaultModel);
                },
              )),
        ],
      ),
    ),
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
