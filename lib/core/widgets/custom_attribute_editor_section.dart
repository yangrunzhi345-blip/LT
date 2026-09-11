import 'package:flutter/material.dart';

import '../../models/custom_attribute_item.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/custom_attribute_importance_visuals.dart';
import 'app_dropdown.dart';

/// 角色卡与 NPC 的统一自添加项（自定义属性）编辑模块
///
/// 遵循 Material 3 与 AGY 纯净白板设计规范：
/// - 默认没有任何预设项（Blank Slate），完全由用户自主按需创建
/// - 支持为每一项单独命名
/// - 支持自定义重要程度：参考、重要参考、很重要参考、不可忽略项
/// - 重要程度下拉选择器使用 [AppDropdown.compact]，默认严格向下弹出
class CustomAttributeEditorSection extends StatefulWidget {
  final List<CustomAttributeItem> initialItems;
  final ValueChanged<List<CustomAttributeItem>> onChanged;
  final String title;
  final String? subtitle;

  const CustomAttributeEditorSection({
    super.key,
    required this.initialItems,
    required this.onChanged,
    this.title = '自添加项',
    this.subtitle = '支持自主为角色/NPC扩展任意专属设定，可单独命名并设置推演重要程度',
  });

  @override
  State<CustomAttributeEditorSection> createState() =>
      _CustomAttributeEditorSectionState();
}

class _CustomAttributeEntry {
  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController valueCtrl;
  CustomAttributeImportance importance;

  _CustomAttributeEntry({
    required this.id,
    required String name,
    required String value,
    required this.importance,
  })  : nameCtrl = TextEditingController(text: name),
        valueCtrl = TextEditingController(text: value);

  void dispose() {
    nameCtrl.dispose();
    valueCtrl.dispose();
  }

  CustomAttributeItem toItem() => CustomAttributeItem(
        id: id,
        name: nameCtrl.text.trim(),
        value: valueCtrl.text.trim(),
        importance: importance,
      );
}

class _CustomAttributeEditorSectionState
    extends State<CustomAttributeEditorSection> {
  final List<_CustomAttributeEntry> _entries = [];
  final List<_CustomAttributeEntry> _pendingDisposal = [];

  @override
  void initState() {
    super.initState();
    for (final item in widget.initialItems) {
      _addEntryFromItem(item);
    }
  }

  void _addEntryFromItem(CustomAttributeItem item) {
    final entry = _CustomAttributeEntry(
      id: item.id.isNotEmpty
          ? item.id
          : DateTime.now().microsecondsSinceEpoch.toString(),
      name: item.name,
      value: item.value,
      importance: item.importance,
    );
    entry.nameCtrl.addListener(_notifyChanged);
    entry.valueCtrl.addListener(_notifyChanged);
    _entries.add(entry);
  }

  void _notifyChanged() {
    widget.onChanged(_entries.map((e) => e.toItem()).toList());
  }

  void _addNewAttribute() {
    setState(() {
      final entry = _CustomAttributeEntry(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: '',
        value: '',
        importance: CustomAttributeImportance.reference,
      );
      entry.nameCtrl.addListener(_notifyChanged);
      entry.valueCtrl.addListener(_notifyChanged);
      _entries.add(entry);
    });
    _notifyChanged();
  }

  void _removeAttribute(int index) {
    if (index < 0 || index >= _entries.length) return;
    final removed = _entries.removeAt(index);
    removed.nameCtrl.removeListener(_notifyChanged);
    removed.valueCtrl.removeListener(_notifyChanged);
    _pendingDisposal.add(removed);
    setState(() {});
    _notifyChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final e in _pendingDisposal) {
        e.dispose();
      }
      _pendingDisposal.clear();
    });
  }

  @override
  void dispose() {
    for (final e in _pendingDisposal) {
      e.dispose();
    }
    _pendingDisposal.clear();
    for (final e in _entries) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题与操作栏
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.playlist_add_rounded,
                  size: 18,
                  color: AppColors.teal,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _entries.isEmpty
                                ? scheme.surfaceContainerHighest
                                : scheme.primaryContainer
                                    .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_entries.length} 项',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _entries.isEmpty
                                  ? scheme.onSurfaceVariant
                                  : scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: _addNewAttribute,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('添加项', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),

          // 列表内容：默认没有时展示白板引导
          if (_entries.isEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.25),
                  style: BorderStyle.solid,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 24,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '暂无自添加项（纯净白板）',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '点击右上角「添加项」可自主定义专属武器、隐秘禁忌、弱点或特质',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ..._entries.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _buildAttributeCard(context, index, item);
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildAttributeCard(
      BuildContext context, int index, _CustomAttributeEntry entry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      key: ValueKey(entry.id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: entry.importance == CustomAttributeImportance.critical
              ? entry.importance.color.withValues(alpha: 0.5)
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: entry.importance == CustomAttributeImportance.critical
              ? 1.5
              : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.2 : 0.03,
            ),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一行：项名称 + 重要程度选择器 (AppDropdown, 默认向下弹出) + 删除按钮
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 名称输入
              Expanded(
                flex: 5,
                child: TextField(
                  controller: entry.nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '项名称 *',
                    hintText: '如: 随身佩剑、致命弱点、施法习惯',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              // 重要程度选择器（使用 AppDropdown，默认向下弹出）
              Expanded(
                flex: 4,
                child: AppDropdown<CustomAttributeImportance>.compact(
                  value: entry.importance,
                  direction: AppDropdownDirection.down,
                  options: CustomAttributeImportance.values
                      .map(
                        (imp) => AppDropdownOption(
                          value: imp,
                          label: imp.label,
                          icon: imp.icon,
                        ),
                      )
                      .toList(),
                  selectedBuilder: (val) {
                    final imp = val ?? CustomAttributeImportance.reference;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(imp.icon, size: 14, color: imp.color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            imp.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  imp == CustomAttributeImportance.critical
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                              color: imp.color,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                  onChanged: (newImp) {
                    if (newImp != null) {
                      setState(() {
                        entry.importance = newImp;
                      });
                      _notifyChanged();
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
              // 删除按钮
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                color: scheme.onSurfaceVariant,
                tooltip: '删除该项',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _removeAttribute(index),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 第二行：项内容 / 详细描述
          TextField(
            controller: entry.valueCtrl,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: '项内容 / 设定描述',
              hintText: '描述该项具体效果、起源或限制（LLM 推演时将遵从对应重要程度）',
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
