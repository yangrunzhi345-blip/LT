import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_dropdown.dart';
import 'package:lt_dialogue/screens/chat/widgets/status_dropdown.dart';
import '../../../../models/adventure_config.dart';
import '../../../../models/custom_attribute_item.dart';
import '../../../../models/equipment.dart';
import '../../../../models/supporting_character.dart';
import '../../../../providers/riverpod_providers.dart';
import 'inventory_screen.dart';

/// 现代化全屏角色状态界面 — 支持主角与队伍同伴多角色切换、战力与能力详情、自定义检测状态、装备随身与身世羁绊
void showCharacterSheet({
  required BuildContext context,
  required String name,
  required String role,
  required int hp,
  required int maxHp,
  required int energy,
  required int maxEnergy,
  required int gold,
  required bool isDark,
  int level = 1,
  int mp = 0,
  int maxMp = 0,
  int skillPoints = 0,
  int baseAtk = 5,
  int baseDef = 3,
  int baseSpeed = 5,
  int experience = 0,
  String? characterId,
  int initialIndex = -1,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CharacterStatusScreen(
        initialName: name,
        initialRole: role,
        initialHp: hp,
        initialMaxHp: maxHp,
        initialEnergy: energy,
        initialMaxEnergy: maxEnergy,
        initialGold: gold,
        isDark: isDark,
        initialLevel: level,
        initialMp: mp,
        initialMaxMp: maxMp,
        initialSkillPoints: skillPoints,
        initialBaseAtk: baseAtk,
        initialBaseDef: baseDef,
        initialBaseSpeed: baseSpeed,
        initialExperience: experience,
        initialCharacterId: characterId,
        initialIndex: initialIndex,
      ),
    ),
  );
}

class CharacterStatusScreen extends ConsumerStatefulWidget {
  final String initialName, initialRole;
  final int initialHp,
      initialMaxHp,
      initialEnergy,
      initialMaxEnergy,
      initialGold;
  final bool isDark;
  final int initialLevel, initialMp, initialMaxMp, initialSkillPoints;
  final int initialBaseAtk, initialBaseDef, initialBaseSpeed, initialExperience;
  final String? initialCharacterId;
  final int initialIndex;

  const CharacterStatusScreen({
    super.key,
    required this.initialName,
    required this.initialRole,
    required this.initialHp,
    required this.initialMaxHp,
    required this.initialEnergy,
    required this.initialMaxEnergy,
    required this.initialGold,
    required this.isDark,
    required this.initialLevel,
    required this.initialMp,
    required this.initialMaxMp,
    required this.initialSkillPoints,
    required this.initialBaseAtk,
    required this.initialBaseDef,
    required this.initialBaseSpeed,
    required this.initialExperience,
    this.initialCharacterId,
    this.initialIndex = -1,
  });

  @override
  ConsumerState<CharacterStatusScreen> createState() =>
      _CharacterStatusScreenState();
}

class _CharacterStatusScreenState extends ConsumerState<CharacterStatusScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late int _selectedCharIndex;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _selectedCharIndex = widget.initialIndex;
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  List<CustomAttributeItem> _getDetectedStatuses({
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
  }) {
    if (isProtagonist) {
      return config?.customAttributes ?? const [];
    } else {
      return companion?.customAttributes ?? const [];
    }
  }

  Future<void> _saveDetectedStatuses(
    List<CustomAttributeItem> updatedList, {
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
  }) async {
    if (config == null) return;
    final chat = ref.read(chatProvider);

    if (isProtagonist) {
      final pName = config.name.trim();
      final taggedList = updatedList
          .map((a) => a.characterName != null && a.characterName!.isNotEmpty
              ? a
              : a.copyWith(characterName: pName))
          .toList();
      final updatedConfig = config.copyWith(customAttributes: taggedList);
      await chat.updateAdventureConfig(updatedConfig);
    } else if (companion != null) {
      final scName = companion.name.trim();
      final taggedList = updatedList
          .map((a) => a.characterName != null && a.characterName!.isNotEmpty
              ? a
              : a.copyWith(characterName: scName))
          .toList();
      final updatedChars = config.supportingCharacters.map((c) {
        if (c.id == companion.id || c.name == companion.name) {
          int? newAffinity;
          for (final a in taggedList) {
            if (a.name.contains('好感') ||
                a.name.toLowerCase().contains('affinity')) {
              if (a.currentValue != null) {
                newAffinity = a.currentValue!.clamp(0, 100);
              } else if (a.isNumeric) {
                newAffinity = a.effectiveCurrentValue.clamp(0, 100);
              }
            }
          }
          return c.copyWith(
            customAttributes: taggedList,
            affinity: newAffinity ?? c.affinity,
          );
        }
        return c;
      }).toList();
      final updatedConfig = config.copyWith(supportingCharacters: updatedChars);
      await chat.updateAdventureConfig(updatedConfig);
    }
    if (mounted) setState(() {});
  }

  void _quickAdjustValue(
    CustomAttributeItem item,
    int index,
    int delta, {
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
  }) {
    final cur = item.effectiveCurrentValue;
    final max = item.effectiveMaxValue;
    final newCur = (cur + delta).clamp(0, max);
    final updatedItem = item.copyWith(
      currentValue: newCur,
      value: '$newCur/$max',
    );
    final currentList = List<CustomAttributeItem>.from(_getDetectedStatuses(
        isProtagonist: isProtagonist, config: config, companion: companion));
    if (index >= 0 && index < currentList.length) {
      currentList[index] = updatedItem;
      _saveDetectedStatuses(currentList,
          isProtagonist: isProtagonist, config: config, companion: companion);
    }
  }

  Future<void> _removeDetectedStatus(
    int index, {
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
  }) async {
    final currentList = List<CustomAttributeItem>.from(_getDetectedStatuses(
        isProtagonist: isProtagonist, config: config, companion: companion));
    if (index >= 0 && index < currentList.length) {
      final target = currentList[index];
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('删除检测状态'),
          content: Text('确定要删除「${target.name}」该检测状态吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('确认删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        currentList.removeAt(index);
        await _saveDetectedStatuses(currentList,
            isProtagonist: isProtagonist, config: config, companion: companion);
      }
    }
  }

  Future<void> _showAddOrEditDetectedStatusDialog({
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
    CustomAttributeItem? editItem,
    int? editIndex,
  }) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isEditing = editItem != null;

    final nameController = TextEditingController(text: editItem?.name ?? '');
    final curValController = TextEditingController(
      text: editItem != null
          ? (editItem.currentValue?.toString() ??
              editItem.effectiveCurrentValue.toString())
          : '100',
    );
    final maxValController = TextEditingController(
      text: editItem != null
          ? (editItem.maxValue?.toString() ??
              editItem.effectiveMaxValue.toString())
          : '100',
    );
    final textValController = TextEditingController(
      text: editItem != null && !editItem.isNumeric ? editItem.value : '',
    );
    final descController =
        TextEditingController(text: editItem?.description ?? '');

    bool isNumericMode = editItem?.isNumeric ?? true;
    String selectedIcon = editItem?.effectiveIcon ?? '🧠';
    CustomAttributeImportance selectedImportance =
        editItem?.importance ?? CustomAttributeImportance.important;

    final availableIcons = [
      '🧠',
      '❤️',
      '☣️',
      '🔥',
      '⚡',
      '💧',
      '🍖',
      '🛡️',
      '👁️',
      '🔮',
      '⭐',
      '⚔️',
      '🩸',
      '💊',
      '✨',
      '🌪️'
    ];

    final presets = [
      (
        label: '🧠 理智(SAN)',
        name: '理智值 (SAN)',
        cur: 100,
        max: 100,
        icon: '🧠',
        desc: '抵抗不可名状与未知恐惧，低于20陷入疯狂幻觉',
        imp: CustomAttributeImportance.critical,
      ),
      (
        label: '❤️ 角色好感',
        name: '好感度',
        cur: 60,
        max: 100,
        icon: '❤️',
        desc: '与角色间的亲密羁绊，达标解锁专属剧情与互动',
        imp: CustomAttributeImportance.important,
      ),
      (
        label: '☣️ 深渊侵蚀',
        name: '深渊侵蚀度',
        cur: 0,
        max: 100,
        icon: '☣️',
        desc: '肉体与精神异变积累，过高将产生异化特征',
        imp: CustomAttributeImportance.critical,
      ),
      (
        label: '🍖 饱食/饥饿',
        name: '饱食度',
        cur: 100,
        max: 100,
        icon: '🍖',
        desc: '探险体力基础，低于30产生虚弱衰竭效果',
        imp: CustomAttributeImportance.reference,
      ),
      (
        label: '🔥 魔力过载',
        name: '魔力过载',
        cur: 0,
        max: 100,
        icon: '🔥',
        desc: '体内暴走能量，过载施法可能自伤或走火入魔',
        imp: CustomAttributeImportance.important,
      ),
      (
        label: '⚡ 精神压力',
        name: '精神压力',
        cur: 10,
        max: 100,
        icon: '⚡',
        desc: '环境恐怖与危机积累的心理重压',
        imp: CustomAttributeImportance.important,
      ),
      (
        label: '🛡️ 护甲韧性',
        name: '护甲耐久',
        cur: 100,
        max: 100,
        icon: '🛡️',
        desc: '防御壁障韧度，优先抵挡外界冲击',
        imp: CustomAttributeImportance.reference,
      ),
      (
        label: '💧 灵力储备',
        name: '灵力储备',
        cur: 100,
        max: 100,
        icon: '💧',
        desc: '施展法术与神通的核心灵气源泉',
        imp: CustomAttributeImportance.important,
      ),
    ];

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 580),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).scaffoldBackgroundColor,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isEditing
                                    ? Icons.edit_note_rounded
                                    : Icons.add_chart_rounded,
                                color: colorScheme.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isEditing ? '编辑检测状态' : '添加检测状态',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () => Navigator.pop(modalCtx),
                              ),
                            ],
                          ),
                          Text(
                            '自定义在冒险故事中持续检测与判定的状态（支持进度槽、判定规则与投骰检定）',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 快捷预设（新增时展示）
                          if (!isEditing) ...[
                            Text(
                              '💡 快捷预设灵感（点击一键填入）:',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              height: 34,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 6),
                                itemCount: presets.length,
                                itemBuilder: (_, i) {
                                  final p = presets[i];
                                  return ActionChip(
                                    label: Text(p.label,
                                        style: const TextStyle(fontSize: 11)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      setModalState(() {
                                        nameController.text = p.name;
                                        curValController.text = '${p.cur}';
                                        maxValController.text = '${p.max}';
                                        descController.text = p.desc;
                                        selectedIcon = p.icon;
                                        selectedImportance = p.imp;
                                        isNumericMode = true;
                                      });
                                    },
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // 状态名称
                          TextField(
                            controller: nameController,
                            decoration: InputDecoration(
                              labelText: '检测状态名称 *',
                              hintText: '例如：理智值(SAN)、好感度、精神污染、饱食度',
                              prefixIcon: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(selectedIcon,
                                    style: const TextStyle(fontSize: 20)),
                              ),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 模式选择
                          Row(
                            children: [
                              Text('计量模式: ',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('数值进度槽 (0~100)'),
                                selected: isNumericMode,
                                onSelected: (v) {
                                  if (v) {
                                    setModalState(() => isNumericMode = true);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: const Text('阶段描述型'),
                                selected: !isNumericMode,
                                onSelected: (v) {
                                  if (v) {
                                    setModalState(() => isNumericMode = false);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 数值或阶段输入
                          if (isNumericMode)
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: curValController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '当前数值',
                                      hintText: '100',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text('/',
                                      style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold)),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: maxValController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '最大上限',
                                      hintText: '100',
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            TextField(
                              controller: textValController,
                              decoration: const InputDecoration(
                                labelText: '当前阶段/描述',
                                hintText: '例如：正常、轻度侵蚀、微醺、狂化中',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),

                          const SizedBox(height: 12),

                          // 图标选择
                          Text('选择状态图标:',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 38,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: availableIcons.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 6),
                              itemBuilder: (_, i) {
                                final ic = availableIcons[i];
                                final isSel = ic == selectedIcon;
                                return InkWell(
                                  onTap: () =>
                                      setModalState(() => selectedIcon = ic),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 38,
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isSel
                                          ? colorScheme.primaryContainer
                                          : colorScheme.surfaceContainerHighest
                                              .withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isSel
                                            ? colorScheme.primary
                                            : Colors.transparent,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Text(ic,
                                        style: const TextStyle(fontSize: 18)),
                                  ),
                                );
                              },
                            ),
                          ),

                          const SizedBox(height: 12),

                          // 规则与判定说明
                          TextField(
                            controller: descController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: '检测规则 / 剧情判定说明 (可选)',
                              hintText: '例如：低于20时陷入恐慌；投骰成功保持理智，失败触发疯狂幻觉',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // AI 剧情遵守级别
                          Row(
                            children: [
                              Text('剧情重要度: ',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: AppDropdown<
                                    CustomAttributeImportance>.compact(
                                  value: selectedImportance,
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
                                    final imp = val ??
                                        CustomAttributeImportance.important;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(imp.icon,
                                            size: 14, color: imp.color),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            imp.label,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: imp ==
                                                      CustomAttributeImportance
                                                          .critical
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              color: imp.color,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                  optionBuilder: (opt) {
                                    final imp = opt.value ??
                                        CustomAttributeImportance.important;
                                    return Row(
                                      children: [
                                        Icon(imp.icon,
                                            size: 15, color: imp.color),
                                        const SizedBox(width: 8),
                                        Text(
                                          imp.label,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: imp ==
                                                    CustomAttributeImportance
                                                        .critical
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                            color: imp.color,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                  onChanged: (v) {
                                    if (v != null) {
                                      setModalState(
                                          () => selectedImportance = v);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // 底部确认按钮
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(modalCtx),
                                child: const Text('取消'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('请输入检测状态名称')),
                                    );
                                    return;
                                  }

                                  final curInt = int.tryParse(
                                          curValController.text.trim()) ??
                                      100;
                                  final maxInt = int.tryParse(
                                          maxValController.text.trim()) ??
                                      100;
                                  final valStr = isNumericMode
                                      ? '$curInt/$maxInt'
                                      : textValController.text.trim();

                                  final newItem = CustomAttributeItem(
                                    id: editItem?.id ??
                                        'detected_${DateTime.now().millisecondsSinceEpoch}',
                                    name: name,
                                    value: isNumericMode
                                        ? (valStr.isNotEmpty
                                            ? valStr
                                            : '$curInt/$maxInt')
                                        : (valStr.isNotEmpty ? valStr : '正常'),
                                    currentValue: isNumericMode ? curInt : null,
                                    maxValue: isNumericMode ? maxInt : null,
                                    icon: selectedIcon,
                                    description: descController.text.trim(),
                                    importance: selectedImportance,
                                  );

                                  final currentList =
                                      List<CustomAttributeItem>.from(
                                    _getDetectedStatuses(
                                      isProtagonist: isProtagonist,
                                      config: config,
                                      companion: companion,
                                    ),
                                  );

                                  if (isEditing &&
                                      editIndex != null &&
                                      editIndex >= 0 &&
                                      editIndex < currentList.length) {
                                    currentList[editIndex] = newItem;
                                  } else {
                                    currentList.add(newItem);
                                  }

                                  Navigator.pop(modalCtx);
                                  await _saveDetectedStatuses(
                                    currentList,
                                    isProtagonist: isProtagonist,
                                    config: config,
                                    companion: companion,
                                  );
                                },
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: Text(isEditing ? '保存修改' : '确认添加'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openDiceCheckDialog(
    CustomAttributeItem item,
    String characterName,
  ) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    int? rolledValue;
    String verdict = '';
    Color verdictColor = colorScheme.primary;
    String verdictEmoji = '🎲';
    bool useD100 = item.isNumeric;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final targetVal = item.effectiveCurrentValue;

            void rollDice() {
              final rng = math.Random();
              final roll =
                  useD100 ? (rng.nextInt(100) + 1) : (rng.nextInt(20) + 1);

              String v;
              Color c;
              String e;

              if (useD100) {
                if (roll <= 5) {
                  v = '大成功 (Critical Success)！判定完美达成！';
                  c = Colors.amber;
                  e = '✨';
                } else if (roll >= 96) {
                  v = '大失败 (Fumble)！遭遇严重失误或异常反噬！';
                  c = Colors.redAccent;
                  e = '💥';
                } else if (roll <= targetVal) {
                  v = '检定成功！成功抵抗异常并维持状态稳定。';
                  c = Colors.green;
                  e = '🛡️';
                } else {
                  v = '检定失败！受到状态影响或负面效果侵扰。';
                  c = Colors.deepOrange;
                  e = '⚠️';
                }
              } else {
                if (roll == 20) {
                  v = '大成功 (暴击)！极限突破达成！';
                  c = Colors.amber;
                  e = '✨';
                } else if (roll == 1) {
                  v = '大失败！判定彻底失败！';
                  c = Colors.redAccent;
                  e = '💥';
                } else if (roll >= 10) {
                  v = '检定通过！状态运转顺利。';
                  c = Colors.green;
                  e = '🛡️';
                } else {
                  v = '检定未通过！受到阻碍或负面波及。';
                  c = Colors.deepOrange;
                  e = '⚠️';
                }
              }

              setDialogState(() {
                rolledValue = roll;
                verdict = v;
                verdictColor = c;
                verdictEmoji = e;
              });
            }

            return AlertDialog(
              title: Row(
                children: [
                  Text(item.effectiveIcon,
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '状态检定 — ${item.name}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('执行角色: $characterName',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        if (item.isNumeric)
                          Text(
                              '检定目标值: $targetVal / ${item.effectiveMaxValue} (掷出 ≤ $targetVal 为成功)',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.bold))
                        else
                          Text('当前状态: ${item.value}',
                              style: const TextStyle(fontSize: 12)),
                        if (item.description?.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text('判定规则: ${item.description}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('D100 百分比骰'),
                        selected: useD100,
                        onSelected: (v) {
                          if (v) setDialogState(() => useD100 = true);
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('D20 骰'),
                        selected: !useD100,
                        onSelected: (v) {
                          if (v) setDialogState(() => useD100 = false);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: rollDice,
                      icon: const Icon(Icons.casino_rounded, size: 20),
                      label: Text(rolledValue == null ? '🎲 投掷检测骰' : '🎲 重新投掷'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ),
                  if (rolledValue != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: verdictColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: verdictColor.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(verdictEmoji,
                                  style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 6),
                              Text(
                                '掷出点数: $rolledValue ${useD100 ? "/ 100" : "/ 20"}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: verdictColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            verdict,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: verdictColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('关闭'),
                ),
                if (rolledValue != null)
                  FilledButton.icon(
                    onPressed: () {
                      final targetDesc = item.isNumeric
                          ? '目标值 $targetVal'
                          : '当前状态 ${item.value}';
                      final ruleNote = item.description?.isNotEmpty == true
                          ? '（规则：${item.description}）'
                          : '';
                      final msg =
                          '【状态检测】$characterName 进行了「${item.name}」检定：🎲 掷出 $rolledValue ($targetDesc) -> 【$verdict】！$ruleNote';
                      ref.read(chatProvider).sendMessage(msg);
                      Navigator.pop(dialogCtx);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.send_rounded, size: 16),
                    label: const Text('同步至冒险剧情'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = widget.isDark;
    final chat = ref.watch(chatProvider);
    final config = chat.adventureConfig;
    final gameState = chat.gameState;

    // 收集当前队伍可用角色：主角 (index: -1) + 随行伙伴
    final supportingChars = config?.supportingCharacters
            .where((sc) => sc.isAlive && sc.name.trim().isNotEmpty)
            .toList() ??
        [];

    final protagonistName = widget.initialName.isNotEmpty
        ? widget.initialName
        : (config?.protagonistCharacter?.characterName.isNotEmpty == true
            ? config!.protagonistCharacter!.characterName
            : (chat.activePersona?.name.isNotEmpty == true
                ? chat.activePersona!.name
                : (config?.name.isNotEmpty == true ? config!.name : '主角')));

    final protagonistRole = widget.initialRole.isNotEmpty
        ? widget.initialRole
        : (config?.protagonistClass.isNotEmpty == true
            ? config!.protagonistClass
            : '探险者');

    // 当前选中的角色数据
    final bool isProtagonist =
        _selectedCharIndex < 0 || _selectedCharIndex >= supportingChars.length;
    final SupportingCharacter? companion =
        isProtagonist ? null : supportingChars[_selectedCharIndex];

    final currentName = isProtagonist ? protagonistName : companion!.name;
    final currentRole = isProtagonist
        ? protagonistRole
        : (companion!.role.isNotEmpty ? companion.role : '队伍同伴');

    final currentHp =
        isProtagonist ? gameState.hp : (companion?.affinity ?? 100);
    final currentMaxHp = isProtagonist ? gameState.maxHp : 100;
    final currentEnergy = isProtagonist ? gameState.energy : 100;
    final currentMaxEnergy = isProtagonist ? gameState.maxEnergy : 100;
    final currentMp = isProtagonist ? gameState.mp : 100;
    final currentMaxMp = isProtagonist ? gameState.maxMp : 100;

    final bg = isDark ? AppColors.darkBackground : AppColors.background;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('角色状态'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        elevation: 0,
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                const SizedBox(height: 8),
                // 队伍多角色快捷切换 Chips（仅当有同伴时展示）
                if (supportingChars.isNotEmpty)
                  Container(
                    height: 42,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemCount: supportingChars.length + 1,
                      itemBuilder: (ctx, i) {
                        final isSelected = i == 0
                            ? isProtagonist
                            : (!isProtagonist && _selectedCharIndex == i - 1);
                        final label = i == 0
                            ? '⭐ $protagonistName (主角)'
                            : supportingChars[i - 1].name;
                        return ChoiceChip(
                          label: Text(label),
                          selected: isSelected,
                          onSelected: (_) {
                            setState(() {
                              _selectedCharIndex = i == 0 ? -1 : i - 1;
                            });
                          },
                          selectedColor: colorScheme.primaryContainer,
                          labelStyle: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),

                // 角色身份卡 Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        // 头像徽章
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: isProtagonist
                                  ? colorScheme.primary
                                  : AppColors.avatarColor(
                                      _selectedCharIndex + 1),
                              child: Text(
                                currentName.isNotEmpty
                                    ? currentName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colorScheme.surface,
                                    width: 1.5,
                                  ),
                                ),
                                child: Text(
                                  isProtagonist
                                      ? 'Lv.${gameState.level}'
                                      : 'NPC',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: AppSpacing.md),
                        // 名字与定位
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      currentName,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      currentRole,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              if (isProtagonist)
                                Text(
                                  config?.protagonistBackground.isNotEmpty ==
                                          true
                                      ? config!.protagonistBackground
                                      : (gameState.currentScene.isNotEmpty
                                          ? '当前探索区域: ${gameState.currentScene}'
                                          : '主线冒险者 · 第 ${gameState.chapter} 篇章'),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              else ...[
                                Row(
                                  children: [
                                    Text(
                                      '关系: ${companion!.relation.isNotEmpty ? companion.relation : "同行伙伴"}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '❤️ 好感度: ${companion.affinity}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: Colors.pinkAccent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // 现代化 TabBar
                TabBar(
                  controller: _tabCtrl,
                  labelColor: colorScheme.primary,
                  unselectedLabelColor: colorScheme.onSurfaceVariant,
                  indicatorColor: colorScheme.primary,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13),
                  tabs: const [
                    Tab(
                        icon: Icon(Icons.analytics_outlined, size: 18),
                        text: '核心状态'),
                    Tab(
                        icon: Icon(Icons.shield_outlined, size: 18),
                        text: '装备随身'),
                    Tab(
                        icon: Icon(Icons.person_outline, size: 18),
                        text: '身世羁绊'),
                  ],
                ),

                // TabBar 内容区
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildStatsTab(
                        context,
                        isProtagonist: isProtagonist,
                        currentName: currentName,
                        hp: currentHp,
                        maxHp: currentMaxHp,
                        mp: currentMp,
                        maxMp: currentMaxMp,
                        energy: currentEnergy,
                        maxEnergy: currentMaxEnergy,
                        gold: gameState.gold,
                        level: gameState.level,
                        exp: gameState.experience,
                        expToNext: gameState.expToNextLevel,
                        atk: gameState.baseAtk,
                        def: gameState.baseDef,
                        spd: gameState.baseSpeed,
                        skillPoints: gameState.skillPoints,
                        scene: gameState.currentScene,
                        detectedStatuses: _getDetectedStatuses(
                          isProtagonist: isProtagonist,
                          config: config,
                          companion: companion,
                        ),
                        onAddDetectedStatus: () =>
                            _showAddOrEditDetectedStatusDialog(
                          isProtagonist: isProtagonist,
                          config: config,
                          companion: companion,
                        ),
                        onEditDetectedStatus: (item, idx) =>
                            _showAddOrEditDetectedStatusDialog(
                          isProtagonist: isProtagonist,
                          config: config,
                          companion: companion,
                          editItem: item,
                          editIndex: idx,
                        ),
                        onRemoveDetectedStatus: (idx) => _removeDetectedStatus(
                          idx,
                          isProtagonist: isProtagonist,
                          config: config,
                          companion: companion,
                        ),
                        onQuickAdjust: (item, idx, delta) => _quickAdjustValue(
                          item,
                          idx,
                          delta,
                          isProtagonist: isProtagonist,
                          config: config,
                          companion: companion,
                        ),
                        onDiceCheck: (item) =>
                            _openDiceCheckDialog(item, currentName),
                      ),
                      _buildGearTab(
                        context,
                        isProtagonist: isProtagonist,
                        characterId: isProtagonist ? null : currentName,
                        adventureId: chat.currentAdventureId,
                      ),
                      _buildProfileTab(
                        context,
                        isProtagonist: isProtagonist,
                        config: config,
                        companion: companion,
                        gameState: gameState,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Tab 1: 核心能力与属性 ───
  Widget _buildStatsTab(
    BuildContext context, {
    required bool isProtagonist,
    required String currentName,
    required int hp,
    required int maxHp,
    required int mp,
    required int maxMp,
    required int energy,
    required int maxEnergy,
    required int gold,
    required int level,
    required int exp,
    required int expToNext,
    required int atk,
    required int def,
    required int spd,
    required int skillPoints,
    required String scene,
    required List<CustomAttributeItem> detectedStatuses,
    required VoidCallback onAddDetectedStatus,
    required void Function(CustomAttributeItem item, int idx)
        onEditDetectedStatus,
    required ValueChanged<int> onRemoveDetectedStatus,
    required void Function(CustomAttributeItem item, int idx, int delta)
        onQuickAdjust,
    required ValueChanged<CustomAttributeItem> onDiceCheck,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // 动态生命与能量状态仪表
        _VitalMeter(
          icon: '❤️',
          label: isProtagonist ? '生命值 (HP)' : '生命活力',
          value: hp,
          max: maxHp,
          barColor: Colors.redAccent,
        ),
        const SizedBox(height: 10),
        _VitalMeter(
          icon: '⚡',
          label: isProtagonist ? '精神魔法 (MP)' : '专注力',
          value: mp,
          max: maxMp,
          barColor: Colors.blueAccent,
        ),
        const SizedBox(height: 10),
        _VitalMeter(
          icon: '🔋',
          label: '行动能量 (Energy)',
          value: energy,
          max: maxEnergy,
          barColor: Colors.teal,
          statusBadge: energy <= 10 ? '⚠️ 疲惫' : '良好',
        ),
        if (isProtagonist) ...[
          const SizedBox(height: 10),
          _VitalMeter(
            icon: '⭐',
            label: '升级经验 (EXP)',
            value: exp,
            max: expToNext,
            barColor: Colors.amber,
            suffix: '下一级需 ${expToNext - exp}',
          ),
        ],

        // ─── 动态检测状态区 (Status Detection & Monitoring) ───
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.radar_outlined, size: 18, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              '自定义检测状态 (${detectedStatuses.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            FilledButton.tonalIcon(
              onPressed: onAddDetectedStatus,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加检测状态',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (detectedStatuses.isEmpty)
          _buildEmptyDetectedStatusCard(context, onAdd: onAddDetectedStatus)
        else
          ...List.generate(detectedStatuses.length, (idx) {
            final item = detectedStatuses[idx];
            return _DetectedStatusCard(
              item: item,
              characterName: currentName,
              onQuickAdjust: (delta) => onQuickAdjust(item, idx, delta),
              onEdit: () => onEditDetectedStatus(item, idx),
              onDelete: () => onRemoveDetectedStatus(idx),
              onDiceCheck: () => onDiceCheck(item),
            );
          }),

        const SizedBox(height: 16),
        Text(
          '战斗与探险能力矩阵',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),

        // 能力矩阵网格卡片
        Row(
          children: [
            _StatCard(
              title: '物理攻击 (ATK)',
              value: '+$atk',
              icon: Icons.flash_on_rounded,
              color: Colors.deepOrange,
            ),
            const SizedBox(width: 8),
            _StatCard(
              title: '基础防御 (DEF)',
              value: '+$def',
              icon: Icons.shield_rounded,
              color: Colors.indigo,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StatCard(
              title: '机敏速度 (SPD)',
              value: '+$spd',
              icon: Icons.speed_rounded,
              color: Colors.teal,
            ),
            const SizedBox(width: 8),
            _StatCard(
              title: '持有金币 (Gold)',
              value: '$gold',
              icon: Icons.monetization_on_rounded,
              color: Colors.amber,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _StatCard(
              title: '可用技能点',
              value: '$skillPoints 点',
              icon: Icons.auto_awesome_rounded,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            _StatCard(
              title: '当前场景坐标',
              value: scene.isNotEmpty ? scene : '起点城镇',
              icon: Icons.explore_rounded,
              color: colorScheme.secondary,
            ),
          ],
        ),
      ],
    );
  }

  // ─── Tab 2: 装备与随身物品 ───
  Widget _buildGearTab(
    BuildContext context, {
    required bool isProtagonist,
    required String? characterId,
    required int? adventureId,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final controller = ref.watch(adventureGameControllerProvider);

    final equipment = controller.equipmentFor(characterId);
    final items = controller.itemsFor(characterId);
    final sharedItems =
        isProtagonist ? controller.itemsFor(null) : <InventoryItem>[];

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Text(
              '⚔️ 当前穿戴装备 (${equipment.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InventoryScreen(adventureId: adventureId),
                  ),
                );
              },
              icon: const Icon(Icons.backpack_outlined, size: 16),
              label: const Text('打开背包仓库'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (equipment.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Center(
              child: Text(
                '暂未穿戴专属装备，可在背包或商店中获取装备提升战力。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...equipment.map((eq) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      eq.icon.isNotEmpty ? eq.icon : '⚔️',
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            eq.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '部位: ${eq.slot.name} · 品质: ${eq.quality.name}',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (eq.stats.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: eq.stats.entries
                            .map((e) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${e.key} +${e.value}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                  ],
                ),
              )),
        const SizedBox(height: 16),
        Text(
          '🎒 随身物品与材料',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty && sharedItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '当前随身行囊无特殊物品。',
              style:
                  TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          )
        else ...[
          ...items.map((item) => _buildItemTile(item, colorScheme)),
          if (sharedItems.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                '📦 公共队伍行囊:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            ...sharedItems.map((item) => _buildItemTile(item, colorScheme)),
          ],
        ],
      ],
    );
  }

  Widget _buildItemTile(InventoryItem item, ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(item.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (item.quantity > 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '×${item.quantity}',
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Tab 3: 身世、性格与人际羁绊 ───
  Widget _buildProfileTab(
    BuildContext context, {
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
    required dynamic gameState,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isProtagonist) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _ProfileSectionCard(
            title: '📜 身份与职业定位',
            content: config?.protagonistClass.isNotEmpty == true
                ? config!.protagonistClass
                : '独自探索未知边界的冒险者，具备机变行动与剧情决策权。',
          ),
          const SizedBox(height: 12),
          _ProfileSectionCard(
            title: '📖 背景经历与渊源',
            content: config?.protagonistBackground.isNotEmpty == true
                ? config!.protagonistBackground
                : (config?.characterCard?.description.isNotEmpty == true
                    ? config!.characterCard!.description
                    : '在风起云涌的世界中踏上征程，经历未知的命运齿轮推演。'),
          ),
          const SizedBox(height: 12),
          _ProfileSectionCard(
            title: '🌍 所处世界观',
            content: config?.worldview.isNotEmpty == true
                ? config!.worldview
                : '沉浸式角色扮演叙事空间，随剧情发展实时推演环境演变。',
          ),
        ],
      );
    }

    // 伙伴详情
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _ProfileSectionCard(
          title: '🎭 性格特质',
          content: companion!.personality.isNotEmpty
              ? companion.personality
              : '性格深沉，在历险旅程中逐步展现内心真正的渴望。',
        ),
        const SizedBox(height: 12),
        _ProfileSectionCard(
          title: '🤝 羁绊与关系',
          content:
              '与主角设定为【${companion.relation.isNotEmpty ? companion.relation : "同伴"}】关系。当前好感度评分: ${companion.affinity}/100。',
        ),
        const SizedBox(height: 12),
        // 外貌细节展示
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✨ 外貌与体态特征',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (companion.gender.isNotEmpty)
                    _Tag('性别: ${companion.gender}'),
                  if (companion.height.isNotEmpty)
                    _Tag('身高: ${companion.height}'),
                  if (companion.hairStyle.isNotEmpty ||
                      companion.hairColor.isNotEmpty)
                    _Tag('发型: ${companion.hairColor} ${companion.hairStyle}'),
                  if (companion.skinTone.isNotEmpty)
                    _Tag('肤色: ${companion.skinTone}'),
                  if (companion.facialFeatures.isNotEmpty)
                    _Tag('面部: ${companion.facialFeatures}'),
                  _Tag(companion.isAlive ? '💚 状态正常' : '💀 失去行动力'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── 状态度量组件 ───

class _VitalMeter extends StatelessWidget {
  final String icon;
  final String label;
  final int value;
  final int max;
  final Color barColor;
  final String? statusBadge;
  final String? suffix;

  const _VitalMeter({
    required this.icon,
    required this.label,
    required this.value,
    required this.max,
    required this.barColor,
    this.statusBadge,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final ratio = max > 0 ? (value / max).clamp(0.0, 1.0) : 1.0;
    final pct = (ratio * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (statusBadge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: barColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusBadge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: barColor,
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              '$value/$max ($pct%)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        if (suffix != null) ...[
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              suffix!,
              style:
                  TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 10,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _ProfileSectionCard extends StatelessWidget {
  final String title;
  final String content;

  const _ProfileSectionCard({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.5,
              color: colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;

  const _Tag(this.text);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: colorScheme.onSurface),
      ),
    );
  }
}

// ─── 自定义检测状态卡片与空态 ───

Widget _buildEmptyDetectedStatusCard(
  BuildContext context, {
  required VoidCallback onAdd,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  return Container(
    padding:
        const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 16),
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(
        color: colorScheme.outlineVariant.withValues(alpha: 0.25),
      ),
    ),
    child: Column(
      children: [
        Icon(Icons.radar_outlined,
            size: 30, color: colorScheme.primary.withValues(alpha: 0.65)),
        const SizedBox(height: 8),
        Text(
          '暂无自定义检测状态',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '支持自定义理智值(SAN)、好感度、精神污染、饱食度、魔力过载等任意冒险状态。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('添加检测状态'),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          ),
        ),
      ],
    ),
  );
}

class _DetectedStatusCard extends StatelessWidget {
  final CustomAttributeItem item;
  final String characterName;
  final ValueChanged<int> onQuickAdjust;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDiceCheck;

  const _DetectedStatusCard({
    required this.item,
    required this.characterName,
    required this.onQuickAdjust,
    required this.onEdit,
    required this.onDelete,
    required this.onDiceCheck,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isNumeric = item.isNumeric;
    final cur = item.effectiveCurrentValue;
    final max = item.effectiveMaxValue;
    final pct = (item.ratio * 100).toInt();

    final statusColor = item.importance.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(item.effectiveIcon,
                    style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.importance.label,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: onDiceCheck,
                icon: const Icon(Icons.casino_outlined, size: 14),
                label: const Text('检定',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
              ),
              StatusDropdown(
                onEdit: onEdit,
                onDelete: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isNumeric) ...[
            Row(
              children: [
                Text(
                  '当前值: ',
                  style: TextStyle(
                      fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
                Text(
                  '$cur / $max ($pct%)',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                _stepperBtn(context, '-5', () => onQuickAdjust(-5)),
                const SizedBox(width: 4),
                _stepperBtn(context, '-1', () => onQuickAdjust(-1)),
                const SizedBox(width: 4),
                _stepperBtn(context, '+1', () => onQuickAdjust(1)),
                const SizedBox(width: 4),
                _stepperBtn(context, '+5', () => onQuickAdjust(5)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: item.ratio,
                minHeight: 7,
                backgroundColor: colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
          ] else ...[
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.psychology_outlined,
                        size: 16, color: statusColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '当前状态阶段 / 心里想法',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.edit_outlined,
                                  size: 12,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.6)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.value.isNotEmpty ? item.value : '（尚未触发阶段判定）',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (item.description != null &&
              item.description!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '📌 规则判定：${item.description!.trim()}',
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepperBtn(
      BuildContext context, String text, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
