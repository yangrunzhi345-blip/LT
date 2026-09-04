import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../../providers/riverpod_providers.dart';
import '../../../providers/chat_provider.dart';
import '../../../models/llm_provider.dart';
import '../../../models/adventure_response.dart';
import '../../../core/theme/app_colors.dart';

/// 复制消息的可见文本：双段响应（叙事 + ---JSON---）只复制叙事部分，
/// 与气泡实际展示内容一致。
Future<void> copyMessageDisplayText(BuildContext context, dynamic message) async {
  final raw = message.content as String;
  final display = AdventureResponse.streamingDisplayText(raw).trim();
  await Clipboard.setData(
      ClipboardData(text: display.isEmpty ? raw : display));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('已复制到剪贴板')),
  );
}

void regenerateMessage(message, ChatProvider provider) {
  final idx = provider.messages.indexOf(message);
  if (idx < 0) {
    debugPrint(
        '[regenerateMessage] indexOf returned -1 for message.id=${message.id}');
    return;
  }

  // 找到要重新发送的用户消息内容，以及该用户消息在列表中的位置
  String? userContent;
  int? deleteFrom; // 从哪个位置开始删除（包含该位置）
  if (message.isUser) {
    userContent = message.content;
    deleteFrom = idx; // 删除该用户消息自身及之后所有内容
  } else {
    // AI 消息：找到前一条用户消息，从该用户消息开始删除
    for (int i = idx - 1; i >= 0; i--) {
      if (provider.messages[i].isUser) {
        userContent = provider.messages[i].content;
        deleteFrom = i; // 从用户消息开始删，避免留下孤立用户消息
        break;
      }
    }
  }

  if (userContent == null || deleteFrom == null) return;
  if (userContent.trim().isEmpty) return;

  // 先删后发：删除从 deleteFrom 开始的所有消息（含用户消息自身）
  final content = userContent; // promote to non-null
  provider.deleteMessagesAfter(deleteFrom);
  // 帧后 sendMessage 会创建一条新用户消息并发送 LLM → 最终只有一条用户消息
  WidgetsBinding.instance.addPostFrameCallback((_) {
    provider.sendMessage(content);
  });
}

void editMessage(message, String newContent, ChatProvider provider) {
  if (newContent.isEmpty || newContent == message.content) return;

  final idx = provider.messages.indexOf(message);
  if (idx < 0) {
    debugPrint(
        '[editMessage] indexOf returned -1 for message.id=${message.id}');
    return;
  }

  if (message.isUser) {
    // 原地替换编辑后的消息
    provider.messages[idx] =
        message.copyWith(content: newContent, isEdited: true);
    // 删除该消息之后的所有 AI 回复
    provider.deleteMessagesAfter(idx + 1);
    // 关键：移除编辑后的用户消息，让 sendMessage 作为唯一用户消息重新添加
    // 否则 sendMessage 会创建第二条内容相同的用户消息（重复气泡 bug）
    provider.messages.removeAt(idx);
    // 帧后发送，确保删除已完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      provider.sendMessage(newContent);
    });
  } else {
    provider.messages[idx] = message.copyWith(content: newContent);
    provider.triggerRebuild();
  }
}

void showEditDialog(BuildContext context, message, ChatProvider provider) {
  final controller = TextEditingController(text: message.content);
  final isUser = message.isUser;

  final sheet = showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit, size: 20),
                const SizedBox(width: 8),
                Text(isUser ? '编辑你的消息' : '编辑 AI 回复',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            if (isUser)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('修改后将从该消息开始重新生成',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 8,
              minLines: 3,
              scrollPadding: const EdgeInsets.only(bottom: 120),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(ctx)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
              ),
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    editMessage(message, controller.text.trim(), provider);
                  },
                  child: Text(isUser ? '修改并重新生成' : '保存修改'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  unawaited(sheet.whenComplete(() => controller.dispose()));
}

void showRegenerateWithModelMenu(
    BuildContext context, message, ChatProvider provider) {
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
                const Text('选择模型重新生成',
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
                  provider.setProvider(p).then((_) {
                    regenerateMessage(message, provider);
                  }).catchError((e) {
                    debugPrint('[RetryMenu] setProvider 失败: $e');
                  });
                },
              )),
          const SizedBox(height: 8),
        ],
      ),
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
                const Text('切换模型',
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
          if (provider.settingsProvider.recentModels.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text('最近使用',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
            ...provider.settingsProvider.recentModels.map((m) => ListTile(
                  leading: const SizedBox(width: 24),
                  title: Text(m, style: const TextStyle(fontSize: 14)),
                  selected: m == provider.modelName,
                  selectedTileColor: AppColors.accent.withValues(alpha: 0.08),
                  trailing: m == provider.modelName
                      ? const Icon(Icons.check_circle,
                          size: 18, color: AppColors.accent)
                      : null,
                  dense: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    provider.setModel(m);
                  },
                )),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                const Icon(Icons.dns_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 6),
                Text('全部提供者',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              ],
            ),
          ),
          ...LLMProvider.values.map((p) => ListTile(
                leading: Icon(
                  Icons.cloud_outlined,
                  color: p == provider.providerType ? AppColors.accent : null,
                ),
                title: Text(p.displayName,
                    style: TextStyle(
                        fontWeight: p == provider.providerType
                            ? FontWeight.w600
                            : FontWeight.normal)),
                subtitle:
                    Text(p.defaultModel, style: const TextStyle(fontSize: 12)),
                trailing: p == provider.providerType
                    ? const Icon(Icons.check_circle,
                        size: 20, color: AppColors.accent)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  provider.setProvider(p);
                },
              )),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

void showInventorySheet(
    BuildContext context, List<String> inventory, bool isDark) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.backpack, size: 20, color: AppColors.accent),
                const SizedBox(width: 8),
                Text('全部装备 (${inventory.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                  tooltip: '返回聊天',
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: inventory.length,
              itemBuilder: (_, i) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.accent,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(inventory[i],
                          style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? const Color(0xFFD0D0D0)
                                  : const Color(0xFF333333))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
