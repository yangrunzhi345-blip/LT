import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/custom_attribute_importance_visuals.dart';
import '../../../../core/widgets/app_dropdown.dart';
import '../../../../core/widgets/app_confirm_dialog.dart';
import '../../../../core/router/app_router.dart';
import '../../../../features/adventure/presentation/session/screens/dice_check_page.dart';
import 'package:lt_dialogue/screens/chat/widgets/status_dropdown.dart';
import '../../../../models/adventure_config.dart';
import '../../../../models/adventure_runtime_state.dart';
import '../../../../models/custom_attribute_item.dart';
import '../../../../models/equipment.dart';
import '../../../../models/supporting_character.dart';
import '../../../../application/adventure/adventure_character_identity.dart';
import '../../../../application/adventure/adventure_character_status_store.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../../providers/adventure_provider.dart';
import 'inventory_screen.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

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
  AppRouter.push<void>(
    context,
    pageBuilder: (_) => CharacterStatusScreen(
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

  /// 找到 [companion] 对应的 selectedCharacters 条目，用于稳定 ID 与快照补建。
  ///
  /// 仅在 ID 命中时返回；没有任何稳定 ID 的历史选择行返回 null，由持久层走
  /// 名称兼容路径，避免这里再造一套身份规则。
  AdventureSelectedCharacter? _selectedCharacterFor(
    AdventureConfig? config,
    SupportingCharacter companion,
  ) {
    for (final selected in config?.selectedCharacters ?? const []) {
      if (selected.isProtagonist) continue;
      if (AdventureCharacterIdentity.candidateIds(selected)
          .contains(companion.id.trim())) {
        return selected;
      }
    }
    return null;
  }

  Map<String, Object?> _runtimeOverlayFor(
    AdventureProvider chat,
    String characterId,
  ) {
    for (final entity in chat.runtimeEntities) {
      if (entity.entityType == RuntimeEntityType.character &&
          entity.entityId == characterId) {
        return entity.overlay;
      }
    }
    return const {};
  }

  Widget _buildCharacterOverviewCard(
    BuildContext context, {
    required String name,
    required String role,
    required int level,
    required int hp,
    required int maxHp,
    required int mp,
    required int maxMp,
    required int energy,
    required int maxEnergy,
    required int experience,
    required int attack,
    required int defense,
    required int speed,
    required List<CustomAttributeItem> statuses,
  }) {
    final l10n = _l10n(context);
    final colors = Theme.of(context).colorScheme;
    Widget meter(String label, int value, int max, Color color) {
      final safeMax = max <= 0 ? 1 : max;
      return SizedBox(
        width: 104,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label $value/$safeMax',
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            LinearProgressIndicator(
              value: (value / safeMax).clamp(0, 1),
              minHeight: 5,
              color: color,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ],
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colors.primary,
                  child: Text(name.isEmpty ? '?' : name.substring(0, 1),
                      style: const TextStyle(color: Colors.white)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(l10n.levelRoleSummary(level, role),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: colors.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                meter('HP', hp, maxHp, Colors.redAccent),
                meter('MP', mp, maxMp, Colors.blueAccent),
                meter(l10n.energyLabel, energy, maxEnergy, Colors.orangeAccent),
                Text('${l10n.experienceLabel} $experience',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.combatStatsSummary(attack, defense, speed),
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
            if (statuses.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final status in statuses)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${status.effectiveIcon} ${status.name} '
                          '${status.value}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveDetectedStatuses(
    List<CustomAttributeItem> updatedList, {
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
    required AdventureSelectedCharacter? selected,
  }) async {
    if (config == null) return;
    final chat = ref.read(chatProvider);

    final AdventureConfig? updatedConfig;
    if (isProtagonist) {
      final taggedList = AdventureCharacterStatusStore.bindCharacterName(
        updatedList,
        config.name,
      );
      updatedConfig = config.copyWith(customAttributes: taggedList);
    } else if (companion != null) {
      // selectedCharacters 是 roster 权威，supportingCharacters 只是自定义检测
      // 状态的兼容持久层：为 selected-only 角色补建 Adventure 自有快照，写回
      // adventures.config，而不是只改一个 UI 临时对象。
      updatedConfig =
          AdventureCharacterStatusStore.writeCompanionCustomAttributes(
        config: config,
        selected: selected,
        fallbackId: companion.id,
        name: companion.name,
        role: companion.role,
        customAttributes: updatedList,
      );
    } else {
      return;
    }
    await chat.updateAdventureConfig(updatedConfig);
    if (mounted) setState(() {});
  }

  void _quickAdjustValue(
    CustomAttributeItem item,
    int index,
    int delta, {
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
    required AdventureSelectedCharacter? selected,
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
          isProtagonist: isProtagonist,
          config: config,
          companion: companion,
          selected: selected);
    }
  }

  Future<void> _removeDetectedStatus(
    int index, {
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
    required AdventureSelectedCharacter? selected,
  }) async {
    final l10n = _l10n(context);
    final currentList = List<CustomAttributeItem>.from(_getDetectedStatuses(
        isProtagonist: isProtagonist, config: config, companion: companion));
    if (index >= 0 && index < currentList.length) {
      final target = currentList[index];
      final confirmed = await AppConfirmDialog.show(
        context: context,
        title: l10n.deleteDetectedStatusTitle,
        message: l10n.confirmDeleteDetectedStatus(target.name),
        confirmLabel: l10n.deleteAction,
        isDanger: true,
      );
      if (confirmed) {
        currentList.removeAt(index);
        await _saveDetectedStatuses(currentList,
            isProtagonist: isProtagonist,
            config: config,
            companion: companion,
            selected: selected);
      }
    }
  }

  Future<void> _showAddOrEditDetectedStatusDialog({
    required bool isProtagonist,
    required AdventureConfig? config,
    required SupportingCharacter? companion,
    required AdventureSelectedCharacter? selected,
    CustomAttributeItem? editItem,
    int? editIndex,
  }) async {
    final l10n = _l10n(context);
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
        label: l10n.statusPresetSanityLabel,
        name: l10n.statusPresetSanityName,
        cur: 100,
        max: 100,
        icon: '🧠',
        desc: l10n.statusPresetSanityDescription,
        imp: CustomAttributeImportance.critical,
      ),
      (
        label: l10n.statusPresetAffinityLabel,
        name: l10n.statusPresetAffinityName,
        cur: 60,
        max: 100,
        icon: '❤️',
        desc: l10n.statusPresetAffinityDescription,
        imp: CustomAttributeImportance.important,
      ),
      (
        label: l10n.statusPresetCorruptionLabel,
        name: l10n.statusPresetCorruptionName,
        cur: 0,
        max: 100,
        icon: '☣️',
        desc: l10n.statusPresetCorruptionDescription,
        imp: CustomAttributeImportance.critical,
      ),
      (
        label: l10n.statusPresetHungerLabel,
        name: l10n.statusPresetHungerName,
        cur: 100,
        max: 100,
        icon: '🍖',
        desc: l10n.statusPresetHungerDescription,
        imp: CustomAttributeImportance.reference,
      ),
      (
        label: l10n.statusPresetMagicLabel,
        name: l10n.statusPresetMagicName,
        cur: 0,
        max: 100,
        icon: '🔥',
        desc: l10n.statusPresetMagicDescription,
        imp: CustomAttributeImportance.important,
      ),
      (
        label: l10n.statusPresetPressureLabel,
        name: l10n.statusPresetPressureName,
        cur: 10,
        max: 100,
        icon: '⚡',
        desc: l10n.statusPresetPressureDescription,
        imp: CustomAttributeImportance.important,
      ),
      (
        label: l10n.statusPresetArmorLabel,
        name: l10n.statusPresetArmorName,
        cur: 100,
        max: 100,
        icon: '🛡️',
        desc: l10n.statusPresetArmorDescription,
        imp: CustomAttributeImportance.reference,
      ),
      (
        label: l10n.statusPresetSpiritLabel,
        name: l10n.statusPresetSpiritName,
        cur: 100,
        max: 100,
        icon: '💧',
        desc: l10n.statusPresetSpiritDescription,
        imp: CustomAttributeImportance.important,
      ),
    ];

    await AppRouter.push<void>(
      context,
      pageBuilder: (modalCtx) => Scaffold(
        appBar: AppBar(
          title: Text(isEditing
              ? l10n.editDetectedStatusTitle
              : l10n.addDetectedStatusAction),
        ),
        body: StatefulBuilder(
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
                                isEditing
                                    ? l10n.editDetectedStatusTitle
                                    : l10n.addDetectedStatusAction,
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
                            l10n.detectedStatusFormDescription,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 快捷预设（新增时展示）
                          if (!isEditing) ...[
                            Text(
                              l10n.statusPresetsHeading,
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
                              labelText: l10n.statusNameLabel,
                              hintText: l10n.statusNameExamples,
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
                              Text(l10n.measurementModeLabel,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: Text(l10n.numericGaugeMode),
                                selected: isNumericMode,
                                onSelected: (v) {
                                  if (v) {
                                    setModalState(() => isNumericMode = true);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: Text(l10n.phaseDescriptionMode),
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
                                    decoration: InputDecoration(
                                      labelText: l10n.currentValueLabel,
                                      hintText: '100',
                                      border: const OutlineInputBorder(),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
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
                                    decoration: InputDecoration(
                                      labelText: l10n.maxValueLabel,
                                      hintText: '100',
                                      border: const OutlineInputBorder(),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 10),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            TextField(
                              controller: textValController,
                              decoration: InputDecoration(
                                labelText: l10n.currentPhaseLabel,
                                hintText: l10n.currentPhaseExamples,
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),

                          const SizedBox(height: 12),

                          // 图标选择
                          Text(l10n.chooseStatusIcon,
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
                            decoration: InputDecoration(
                              labelText: l10n.statusRuleLabel,
                              hintText: l10n.statusRuleHint,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // AI 剧情遵守级别
                          Row(
                            children: [
                              Text(l10n.storyImportanceLabel,
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
                                          label: imp.localizedLabel(l10n),
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
                                            imp.localizedLabel(l10n),
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
                                          imp.localizedLabel(l10n),
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
                                child: Text(l10n.cancelAction),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () async {
                                  final name = nameController.text.trim();
                                  if (name.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              l10n.statusNameRequiredError)),
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
                                        : (valStr.isNotEmpty
                                            ? valStr
                                            : l10n.goodStatus),
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
                                    selected: selected,
                                  );
                                },
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: Text(isEditing
                                    ? l10n.saveAction
                                    : l10n.confirmAction),
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
        ),
      ),
    );
  }

  Future<void> _openDiceCheckDialog(
    CustomAttributeItem item,
    String characterName,
  ) async {
    final message = await AppRouter.push<String>(
      context,
      pageBuilder: (_) => DiceCheckPage(
        item: item,
        characterName: characterName,
      ),
    );
    if (!mounted || message == null) return;
    ref.read(chatProvider).sendMessage(message);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = widget.isDark;
    final chat = ref.watch(chatProvider);
    final config = chat.adventureConfig;
    final gameState = chat.gameState;

    // 收集当前队伍可用角色：主角 (index: -1) + 随行伙伴
    final supportingChars = <SupportingCharacter>[
      ...(config?.supportingCharacters
              .where((sc) => sc.name.trim().isNotEmpty)
              .toList() ??
          const <SupportingCharacter>[]),
    ];
    // selectedCharacters is the frozen assembly roster.  Some newer
    // adventures intentionally have no corresponding legacy
    // supportingCharacters row, so materialize a lightweight view entry for
    // every selected non-protagonist instead of silently dropping it.
    for (final selected in config?.selectedCharacters ?? const []) {
      if (selected.isProtagonist || selected.characterName.trim().isEmpty) {
        continue;
      }
      final selectedIds = AdventureCharacterIdentity.candidateIds(selected);
      if (supportingChars
          .any((character) => selectedIds.contains(character.id.trim()))) {
        continue;
      }
      supportingChars.add(SupportingCharacter(
        id: AdventureCharacterIdentity.effectiveId(selected),
        name: selected.characterName,
        role: selected.effectiveRole,
      ));
    }

    final protagonistName = widget.initialName.isNotEmpty
        ? widget.initialName
        : (config?.protagonistCharacter?.characterName.isNotEmpty == true
            ? config!.protagonistCharacter!.characterName
            : (chat.activePersona?.name.isNotEmpty == true
                ? chat.activePersona!.name
                : (config?.name.isNotEmpty == true
                    ? config!.name
                    : l10n.mainProtagonistTitle)));

    final protagonistRole = widget.initialRole.isNotEmpty
        ? widget.initialRole
        : (config?.protagonistClass.isNotEmpty == true
            ? config!.protagonistClass
            : l10n.explorerRole);

    // 当前选中的角色数据
    final bool isProtagonist =
        _selectedCharIndex < 0 || _selectedCharIndex >= supportingChars.length;
    final SupportingCharacter? companion =
        isProtagonist ? null : supportingChars[_selectedCharIndex];
    // 稳定身份的权威来源：selectedCharacters 决定角色存在，运行期实体与检测状态
    // 快照都必须落在同一个 ID 上。
    final AdventureSelectedCharacter? selectedCompanion =
        companion == null ? null : _selectedCharacterFor(config, companion);

    final currentName = isProtagonist ? protagonistName : companion!.name;
    final currentRole = isProtagonist
        ? protagonistRole
        : (companion!.role.isNotEmpty
            ? companion.role
            : l10n.relationCompanion);

    final protagonistId =
        config?.protagonistCharacter?.characterId ?? 'protagonist';
    final selectedRuntimeId = isProtagonist
        ? protagonistId
        : companion!.id.trim().isNotEmpty
            ? companion.id
            : currentName;
    final selectedOverlay = _runtimeOverlayFor(
      chat.adventureProvider,
      selectedRuntimeId,
    );
    int runtimeInt(String key, int fallback) =>
        (selectedOverlay[key] as num?)?.toInt() ?? fallback;

    final currentHp = runtimeInt('hp', isProtagonist ? gameState.hp : 100);
    final currentMaxHp =
        runtimeInt('max_hp', isProtagonist ? gameState.maxHp : 100);
    final currentEnergy =
        runtimeInt('energy', isProtagonist ? gameState.energy : 100);
    final currentMaxEnergy =
        runtimeInt('max_energy', isProtagonist ? gameState.maxEnergy : 100);
    final currentMp = runtimeInt('mp', isProtagonist ? gameState.mp : 100);
    final currentMaxMp =
        runtimeInt('max_mp', isProtagonist ? gameState.maxMp : 100);
    final currentLevel =
        runtimeInt('level', isProtagonist ? gameState.level : 1);
    final currentExperience =
        runtimeInt('experience', isProtagonist ? gameState.experience : 0);
    final currentAttack =
        runtimeInt('base_atk', isProtagonist ? gameState.baseAtk : 5);
    final currentDefense =
        runtimeInt('base_def', isProtagonist ? gameState.baseDef : 3);
    final currentSpeed =
        runtimeInt('base_speed', isProtagonist ? gameState.baseSpeed : 5);

    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final protagonistOverlay =
        _runtimeOverlayFor(chat.adventureProvider, protagonistId);
    final protagonistHp =
        (protagonistOverlay['hp'] as num?)?.toInt() ?? gameState.hp;
    final protagonistMp =
        (protagonistOverlay['mp'] as num?)?.toInt() ?? gameState.mp;
    final protagonistEnergy =
        (protagonistOverlay['energy'] as num?)?.toInt() ?? gameState.energy;
    final protagonistLevel =
        (protagonistOverlay['level'] as num?)?.toInt() ?? gameState.level;
    final protagonistExperience =
        (protagonistOverlay['experience'] as num?)?.toInt() ??
            gameState.experience;
    final protagonistAttack =
        (protagonistOverlay['base_atk'] as num?)?.toInt() ?? gameState.baseAtk;
    final protagonistDefense =
        (protagonistOverlay['base_def'] as num?)?.toInt() ?? gameState.baseDef;
    final protagonistSpeed =
        (protagonistOverlay['base_speed'] as num?)?.toInt() ??
            gameState.baseSpeed;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(l10n.characterStatusTitle),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: l10n.backAction,
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
                            ? '⭐ $protagonistName (${l10n.mainProtagonistTitle})'
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

                // Runtime state is per assembled character, not per selected
                // actor. Keep the complete team visible on the status page.
                Flexible(
                  fit: FlexFit.loose,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        _buildCharacterOverviewCard(
                          context,
                          name: protagonistName,
                          role: protagonistRole,
                          level: protagonistLevel,
                          hp: protagonistHp,
                          maxHp: gameState.maxHp,
                          mp: protagonistMp,
                          maxMp: gameState.maxMp,
                          energy: protagonistEnergy,
                          maxEnergy: gameState.maxEnergy,
                          experience: protagonistExperience,
                          attack: protagonistAttack,
                          defense: protagonistDefense,
                          speed: protagonistSpeed,
                          statuses: config?.customAttributes ?? const [],
                        ),
                        for (final character in supportingChars)
                          Builder(builder: (context) {
                            final overlay = _runtimeOverlayFor(
                                chat.adventureProvider, character.id);
                            return _buildCharacterOverviewCard(
                              context,
                              name: character.name,
                              role: character.role.isEmpty
                                  ? l10n.relationCompanion
                                  : character.role,
                              level: (overlay['level'] as num?)?.toInt() ?? 1,
                              hp: (overlay['hp'] as num?)?.toInt() ?? 100,
                              maxHp:
                                  (overlay['max_hp'] as num?)?.toInt() ?? 100,
                              mp: (overlay['mp'] as num?)?.toInt() ?? 100,
                              maxMp:
                                  (overlay['max_mp'] as num?)?.toInt() ?? 100,
                              energy:
                                  (overlay['energy'] as num?)?.toInt() ?? 100,
                              maxEnergy:
                                  (overlay['max_energy'] as num?)?.toInt() ??
                                      100,
                              experience:
                                  (overlay['experience'] as num?)?.toInt() ?? 0,
                              attack:
                                  (overlay['base_atk'] as num?)?.toInt() ?? 5,
                              defense:
                                  (overlay['base_def'] as num?)?.toInt() ?? 3,
                              speed:
                                  (overlay['base_speed'] as num?)?.toInt() ?? 5,
                              statuses: character.customAttributes,
                            );
                          }),
                      ],
                    ),
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
                                          ? l10n.currentExplorationRegion(
                                              gameState.currentScene,
                                            )
                                          : l10n.mainStoryChapter(
                                              gameState.chapter,
                                            )),
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
                                      l10n.relationshipLabel(
                                        companion!.relation.isNotEmpty
                                            ? companion.relation
                                            : l10n.relationCompanion,
                                      ),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      l10n.affinityScoreLabel(
                                          companion.affinity),
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
                  tabs: [
                    Tab(
                        icon: const Icon(Icons.analytics_outlined, size: 18),
                        text: l10n.companionsTab),
                    Tab(
                        icon: const Icon(Icons.shield_outlined, size: 18),
                        text: l10n.equipmentTab),
                    Tab(
                        icon: const Icon(Icons.person_outline, size: 18),
                        text: l10n.profileTab),
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
                        level: currentLevel,
                        exp: currentExperience,
                        expToNext: currentLevel * 100,
                        atk: currentAttack,
                        def: currentDefense,
                        spd: currentSpeed,
                        skillPoints: isProtagonist ? gameState.skillPoints : 0,
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
                          selected: selectedCompanion,
                        ),
                        onEditDetectedStatus: (item, idx) =>
                            _showAddOrEditDetectedStatusDialog(
                          isProtagonist: isProtagonist,
                          config: config,
                          companion: companion,
                          selected: selectedCompanion,
                          editItem: item,
                          editIndex: idx,
                        ),
                        onRemoveDetectedStatus: (idx) => _removeDetectedStatus(
                          idx,
                          isProtagonist: isProtagonist,
                          config: config,
                          companion: companion,
                          selected: selectedCompanion,
                        ),
                        onQuickAdjust: (item, idx, delta) => _quickAdjustValue(
                          item,
                          idx,
                          delta,
                          isProtagonist: isProtagonist,
                          config: config,
                          companion: companion,
                          selected: selectedCompanion,
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
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // 动态生命与能量状态仪表
        _VitalMeter(
          icon: '❤️',
          label: isProtagonist ? l10n.healthPointsLabel : l10n.lifeForceLabel,
          value: hp,
          max: maxHp,
          barColor: Colors.redAccent,
        ),
        const SizedBox(height: 10),
        _VitalMeter(
          icon: '⚡',
          label: isProtagonist ? l10n.magicPointsLabel : l10n.focusLabel,
          value: mp,
          max: maxMp,
          barColor: Colors.blueAccent,
        ),
        const SizedBox(height: 10),
        _VitalMeter(
          icon: '🔋',
          label: l10n.actionEnergyLabel,
          value: energy,
          max: maxEnergy,
          barColor: Colors.teal,
          statusBadge: energy <= 10 ? l10n.tiredStatus : l10n.goodStatus,
        ),
        if (isProtagonist) ...[
          const SizedBox(height: 10),
          _VitalMeter(
            icon: '⭐',
            label: l10n.experienceLabel,
            value: exp,
            max: expToNext,
            barColor: Colors.amber,
            suffix: l10n.nextLevelExperience(expToNext - exp),
          ),
        ],

        // ─── 动态检测状态区 (Status Detection & Monitoring) ───
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.radar_outlined,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.detectedStatusesCount(detectedStatuses.length),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: onAddDetectedStatus,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(l10n.addDetectedStatusAction,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
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
          l10n.combatAdventureMatrix,
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
              title: l10n.physicalAttackStat,
              value: '+$atk',
              icon: Icons.flash_on_rounded,
              color: Colors.deepOrange,
            ),
            const SizedBox(width: 8),
            _StatCard(
              title: l10n.baseDefenseStat,
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
              title: l10n.agilitySpeedStat,
              value: '+$spd',
              icon: Icons.speed_rounded,
              color: Colors.teal,
            ),
            const SizedBox(width: 8),
            _StatCard(
              title: l10n.goldStat,
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
              title: l10n.availableSkillPointsStat,
              value: l10n.skillPointsValue(skillPoints),
              icon: Icons.auto_awesome_rounded,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            _StatCard(
              title: l10n.currentSceneCoordinatesStat,
              value: scene.isNotEmpty ? scene : l10n.startingTown,
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
    final l10n = _l10n(context);
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
              l10n.equippedGearCount(equipment.length),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                AppRouter.pushReplacement<void, void>(
                  context,
                  pageBuilder: (_) => InventoryScreen(adventureId: adventureId),
                );
              },
              icon: const Icon(Icons.backpack_outlined, size: 16),
              label: Text(l10n.openInventoryAction),
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
                l10n.noEquippedGear,
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
                            l10n.gearSlotQuality(eq.slot.name, eq.quality.name),
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
          l10n.carriedItemsTitle,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty && sharedItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.noCarriedItems,
              style:
                  TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          )
        else ...[
          ...items.map((item) => _buildItemTile(item, colorScheme)),
          if (sharedItems.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(
                l10n.sharedPartyInventory,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
    final l10n = _l10n(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isProtagonist) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _ProfileSectionCard(
            title: l10n.profileIdentityTitle,
            content: config?.protagonistClass.isNotEmpty == true
                ? config!.protagonistClass
                : l10n.defaultProtagonistProfile,
          ),
          const SizedBox(height: 12),
          _ProfileSectionCard(
            title: l10n.profileBackgroundTitle,
            content: config?.protagonistBackground.isNotEmpty == true
                ? config!.protagonistBackground
                : (config?.characterCard?.description.isNotEmpty == true
                    ? config!.characterCard!.description
                    : l10n.defaultProtagonistBackground),
          ),
          const SizedBox(height: 12),
          _ProfileSectionCard(
            title: l10n.profileWorldviewTitle,
            content: config?.worldview.isNotEmpty == true
                ? config!.worldview
                : l10n.defaultWorldviewDescription,
          ),
        ],
      );
    }

    // 伙伴详情
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _ProfileSectionCard(
          title: l10n.profilePersonalityTitle,
          content: companion!.personality.isNotEmpty
              ? companion.personality
              : l10n.defaultCompanionPersonality,
        ),
        const SizedBox(height: 12),
        _ProfileSectionCard(
          title: l10n.profileRelationshipsTitle,
          content: l10n.companionRelationshipSummary(
            companion.relation.isNotEmpty
                ? companion.relation
                : l10n.relationCompanion,
            companion.affinity,
          ),
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
                l10n.profileAppearanceTitle,
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
                    _Tag(l10n.genderTag(companion.gender)),
                  if (companion.height.isNotEmpty)
                    _Tag(l10n.heightTag(companion.height)),
                  if (companion.hairStyle.isNotEmpty ||
                      companion.hairColor.isNotEmpty)
                    _Tag(l10n.hairstyleTag(
                        '${companion.hairColor} ${companion.hairStyle}')),
                  if (companion.skinTone.isNotEmpty)
                    _Tag(l10n.skinToneTag(companion.skinTone)),
                  if (companion.facialFeatures.isNotEmpty)
                    _Tag(l10n.facialFeaturesTag(companion.facialFeatures)),
                  _Tag(companion.isAlive
                      ? l10n.aliveStatus
                      : l10n.incapacitatedStatus),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    softWrap: true,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (statusBadge != null)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
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
              ),
            ),
            const SizedBox(width: 8),
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
  final l10n = _l10n(context);
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
          l10n.noCustomDetectedStatuses,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.detectedStatusesEmptyDescription,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: Text(l10n.addDetectedStatusAction),
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
    final l10n = _l10n(context);
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.importance.localizedLabel(_l10n(context)),
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
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onDiceCheck,
                    icon: const Icon(Icons.casino_outlined, size: 14),
                    label: Text(l10n.checkAction,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                    ),
                  ),
                  StatusDropdown(
                    onEdit: onEdit,
                    onDelete: onDelete,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (isNumeric) ...[
            Row(
              children: [
                Text(
                  l10n.currentValuePrefix,
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
                                l10n.currentPhaseWithThoughtsLabel,
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
                            item.value.isNotEmpty
                                ? item.value
                                : l10n.phaseNotTriggered,
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
                l10n.statusRulePrefix(item.description!.trim()),
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
