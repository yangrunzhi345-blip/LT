import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../../providers/riverpod_providers.dart';
import '../../../providers/chat_provider.dart';
import '../../../domain/read_aloud/read_aloud_contracts.dart';
import '../../../models/adventure_response.dart';
import '../../../models/message.dart';
import '../../../core/router/app_router.dart';
import '../../../core/localization/app_error_localizer.dart';
import '../../../features/adventure/presentation/session/screens/model_select_page.dart';
import '../../../features/adventure/presentation/session/screens/message_edit_page.dart';
import 'inventory_screen.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/generated/app_localizations_zh.dart';

/// 复制消息的可见文本：双段响应（叙事 + ---JSON---）只复制叙事部分，
/// 与气泡实际展示内容一致。
Future<void> copyMessageDisplayText(
    BuildContext context, dynamic message) async {
  final raw = message.content as String;
  final display = AdventureResponse.streamingDisplayText(raw).trim();
  await Clipboard.setData(ClipboardData(text: display.isEmpty ? raw : display));
  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(l10n.messageCopied)),
  );
}

/// 朗读一条 AI 回复的“可见正文”。
///
/// 双段响应（叙事 + `---JSON---`）只朗读叙事部分，思维链不参与；具体清洗与
/// 分段由全局朗读 Authority 负责，这里只提供正确的可见文本与来源标识。
Future<void> readAloudMessage(
  BuildContext context,
  dynamic message,
  ChatProvider provider,
) {
  final raw = message.content as String;
  final visible = AdventureResponse.streamingDisplayText(raw).trim();
  final sessionId = 'chat:${message.id}';
  return provider.settingsProvider.readAloud.playText(
    visible.isEmpty ? raw : visible,
    sourceId: sessionId,
    sourceType: ReadAloudSourceType.chat,
    label: (AppLocalizations.of(context) ?? AppLocalizationsZh()).aiReplyLabel,
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
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      return SafeArea(
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
                title: Text(l10n.chatEditMessage),
                onTap: () {
                  Navigator.pop(ctx);
                  showEditDialog(context, message, provider);
                },
              ),
            if (!isUser)
              ListTile(
                leading: const Icon(Icons.volume_up),
                title: Text(l10n.readAloudStart),
                onTap: () {
                  Navigator.pop(ctx);
                  final capability =
                      provider.settingsProvider.readAloud.capability;
                  if (!capability.supported) {
                    // 明确的平台能力提示，而不是静默什么都不发生。
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          localizeReadAloudCapability(l10n, capability),
                        ),
                      ),
                    );
                    return;
                  }
                  unawaited(readAloudMessage(context, message, provider));
                },
              ),
            if (!isUser &&
                message.reasoningContent != null &&
                (message.reasoningContent as String).trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: Text(l10n.chatCopyReasoning),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(
                      ClipboardData(text: message.reasoningContent as String));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.chatReasoningCopied)),
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(l10n.chatRetryWithModel),
              onTap: () {
                Navigator.pop(ctx);
                showRegenerateWithModelMenu(context, message, provider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.call_split),
              title: Text(l10n.chatFork),
              onTap: () {
                Navigator.pop(ctx);
                final idx = provider.messages.indexOf(message);
                if (idx >= 0) {
                  provider.forkAdventure(idx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l10n.chatBranchCreated(provider.currentBranchId),
                      ),
                    ),
                  );
                }
              },
            ),
            if (!isUser)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  l10n.chatDeleteMessage,
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  provider.deleteMessage(message);
                },
              ),
          ],
        ),
      );
    },
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
