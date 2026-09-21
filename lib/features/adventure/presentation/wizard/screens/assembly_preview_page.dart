import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/app_card.dart';
import '../../../../../core/widgets/app_read_aloud.dart';
import '../../../../../core/widgets/ui_foundation.dart';
import '../../../../../domain/read_aloud/read_aloud_contracts.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../application/adventure/adventure_readiness_gate.dart';

/// 组装预览页中对用户可见的世界设定正文（与页面实际渲染内容保持一致）。
String _worldReadAloudText(AdventureConfig cfg, String? desc) {
  if (desc != null && desc.isNotEmpty) return desc;
  return cfg.worldview.isNotEmpty ? '已绑定世界观规则与地理法则' : '使用默认大陆规则';
}

/// 组装最终总览与准备确认独立页面 (Assembly Preview Page)
///
/// 遵循 R02 UI Foundation 规范：
/// AppPageScaffold + AppCard + AppPrimaryButton
/// 支持 320px 窄屏适配，无 RenderFlex overflow。
class AssemblyPreviewPage extends ConsumerStatefulWidget {
  final AdventureConfig config;
  final String? worldviewDesc;
  final Future<void> Function(AdventureConfig config)? onStartAdventure;
  final VoidCallback? onEditWorldview;
  final VoidCallback? onEditCharacters;
  final VoidCallback? onEditConfig;

  const AssemblyPreviewPage({
    super.key,
    required this.config,
    this.worldviewDesc,
    this.onStartAdventure,
    this.onEditWorldview,
    this.onEditCharacters,
    this.onEditConfig,
  });

  @override
  ConsumerState<AssemblyPreviewPage> createState() =>
      _AssemblyPreviewPageState();
}

class _AssemblyPreviewPageState extends ConsumerState<AssemblyPreviewPage> {
  bool _submitting = false;

  /// One-shot latch: once this launch succeeded the page must never offer
  /// 「踏入冒险」 again, so a second (slow or animation-time) tap cannot create a
  /// duplicate Adventure.
  bool _launched = false;
  bool _readinessLoading = true;
  bool _retryingReadiness = false;
  Map<String, AdventureAssetReadiness> _readiness =
      const <String, AdventureAssetReadiness>{};
  String? _readinessError;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReadiness();
  }

  Future<void> _loadReadiness() async {
    try {
      final statuses = await ref
          .read(adventureReadinessGateProvider)
          .resolveConfig(widget.config);
      if (!mounted) return;
      setState(() {
        _readiness = statuses;
        _readinessLoading = false;
        _readinessError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _readinessLoading = false;
        _readinessError = error.toString();
        _errorMessage = '无法读取资源就绪状态：$error';
      });
    }
  }

  Future<void> _retryReadiness() async {
    if (_retryingReadiness || _readinessLoading) return;
    final blocked = _readiness.values.where(
      (item) => item.isManaged && item.status != AdventureAssetGateStatus.ready,
    );
    if (blocked.isEmpty) return;
    setState(() {
      _retryingReadiness = true;
      _readinessError = null;
      _errorMessage = null;
    });
    try {
      final gate = ref.read(adventureReadinessGateProvider);
      for (final item in blocked) {
        await gate.prepare(item.assetId);
      }
      await _loadReadiness();
    } catch (error) {
      if (mounted) {
        setState(() {
          _readinessError = '$error';
          _errorMessage = '资源重新准备失败：$error';
        });
      }
    } finally {
      if (mounted) setState(() => _retryingReadiness = false);
    }
  }

  bool get _assemblyReady =>
      !_readinessLoading &&
      _readinessError == null &&
      _readiness.values.every(
        (item) =>
            item.status == AdventureAssetGateStatus.ready ||
            item.status == AdventureAssetGateStatus.notManaged,
      );

  Future<void> _handleStart() async {
    if (_submitting || _launched) return;
    if (widget.onStartAdventure == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final gate = ref.read(adventureReadinessGateProvider);
      final frozen = await gate.enforceAndFreeze(widget.config);
      await widget.onStartAdventure!(frozen);
      if (!mounted) return;
      // MainGate / ChatProvider 是会话导航 Authority：只有确认会话已经就绪，
      // 才允许退出装配页，并且一次退到 MainGate，而不是只 pop 掉预览页再回到
      // AssemblyCreatePage —— 那正是「点了没反应」并重复创建同一个 Adventure 的根因。
      if (_confirmSessionReady()) return;
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '启动冒险失败：$e');
      }
    } finally {
      if (mounted && !_launched) {
        setState(() => _submitting = false);
      }
    }
  }

  /// Leaves the whole assembly route stack once the ChatProvider reports a
  /// usable session. Returns whether the launch was confirmed and the stack
  /// exited; a failed launch stays on this page so the user can retry.
  bool _confirmSessionReady() {
    final chat = ref.read(chatProvider);
    if (!chat.isAdventureChatOpen || chat.currentAdventureId == null) {
      return false;
    }
    _launched = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cfg = widget.config;

    final protagonist =
        cfg.selectedCharacters.where((c) => c.isProtagonist).firstOrNull;
    final protagonistName = protagonist?.characterName.isNotEmpty ?? false
        ? protagonist!.characterName
        : (cfg.name.isNotEmpty ? cfg.name : '无名勇者');
    final protagonistClass =
        cfg.protagonistClass.isNotEmpty ? cfg.protagonistClass : '冒险者';

    final otherCharacters =
        cfg.selectedCharacters.where((c) => !c.isProtagonist).toList();

    return AppPageScaffold(
      title: '冒险装配总览',
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('冒险装配总览', style: theme.textTheme.titleMedium),
          Text(
            '全面检查世界观、角色阵容、NPC 与序章推演设定',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      bottomBar: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              if (_errorMessage != null) ...[
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: scheme.error,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ] else
                const Spacer(),
              AppPrimaryButton(
                key: const Key('assembly-preview-start-button'),
                label: '踏入冒险',
                isLoading: _submitting,
                onPressed: _launched || !_assemblyReady || _submitting
                    ? null
                    : _handleStart,
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 就绪提示栏
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: scheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _readinessLoading
                              ? '正在检查资源装配状态'
                              : _readinessError != null
                                  ? '无法确认资源装配状态'
                                  : _assemblyReady
                                      ? '冒险要素装配完毕'
                                      : '仍有资源未完成装配',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _readinessLoading
                              ? '正在读取世界观与角色的可用版本。'
                              : _readinessError != null
                                  ? '资源状态读取失败，为安全起见暂不能确认可启动。'
                                  : _assemblyReady
                                      ? '点击下方「踏入冒险」即可冻结快照并开启全新旅程。'
                                      : '缺少可用版本时无法踏入冒险，请先完成资源组装准备。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (!_readinessLoading &&
                            _readinessError == null &&
                            !_assemblyReady) ...[
                          const SizedBox(height: AppSpacing.xs),
                          ..._readiness.values
                              .where((item) =>
                                  item.isManaged &&
                                  item.status != AdventureAssetGateStatus.ready)
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    item.message,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.error,
                                    ),
                                  ),
                                ),
                              ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: const Key('assembly-preview-retry-button'),
                              onPressed:
                                  _retryingReadiness ? null : _retryReadiness,
                              child: Text(
                                _retryingReadiness ? '正在重新准备…' : '重新准备',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 1. 世界观设定卡片
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.public_rounded,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '世界设定: ${cfg.worldview.isNotEmpty ? cfg.worldview : "自定义世界"}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.onEditWorldview != null)
                        TextButton(
                          onPressed: widget.onEditWorldview,
                          child: const Text('修改'),
                        ),
                      AppReadAloudButton(
                        sourceId: 'assembly-preview:worldview',
                        sourceType: ReadAloudSourceType.assemblyPreview,
                        text: _worldReadAloudText(cfg, widget.worldviewDesc),
                        label: '世界设定',
                        tooltip: '朗读世界设定',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _worldReadAloudText(cfg, widget.worldviewDesc),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
                  const AppReadAloudControls(
                      sourceId: 'assembly-preview:worldview'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // 2. 主角与阵容卡片
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person_rounded,
                          size: 20, color: scheme.secondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '主控主角: $protagonistName ($protagonistClass)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.onEditCharacters != null)
                        TextButton(
                          onPressed: widget.onEditCharacters,
                          child: const Text('修改'),
                        ),
                    ],
                  ),
                  if (cfg.personality.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '性格特点: ${cfg.personality}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (cfg.protagonistBackground.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '背景身世: ${cfg.protagonistBackground}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (otherCharacters.isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      '同行角色 (${otherCharacters.length} 位):',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: otherCharacters.map((c) {
                        final roleLabel = AdventureCharacterRole.labelOf(
                            c.narrativeRole,
                            customName: c.customRoleName);
                        return Chip(
                          avatar: const Icon(Icons.group_rounded, size: 14),
                          label: Text('${c.characterName} · $roleLabel'),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],
                  if (cfg.characterRelationships.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '羁绊关系 (${cfg.characterRelationships.length} 条):',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...cfg.characterRelationships.map((rel) {
                      final relName = AdventureRelationType.labelOf(
                          rel.relationType,
                          customName: rel.customRelationName);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '• ${rel.sourceCharacterId} ↔ ${rel.targetCharacterId}：$relName',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),

            // 3. NPC 卡片
            if (cfg.npcSnapshots.isNotEmpty) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.record_voice_over_rounded,
                            size: 20, color: scheme.tertiary),
                        const SizedBox(width: 8),
                        Text(
                          '常驻 NPC (${cfg.npcSnapshots.length} 位)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: cfg.npcSnapshots.map((npc) {
                        return Chip(
                          label: Text(npc.name),
                          visualDensity: VisualDensity.compact,
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            // 4. 序章与分支卡片
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.menu_book_rounded,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '序章开场与行动决策',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.onEditConfig != null)
                        TextButton(
                          onPressed: widget.onEditConfig,
                          child: const Text('修改'),
                        ),
                      if (cfg.openingScene.isNotEmpty)
                        AppReadAloudButton(
                          sourceId: 'assembly-preview:opening',
                          sourceType: ReadAloudSourceType.assemblyPreview,
                          text: cfg.openingScene,
                          label: '序章开场',
                          tooltip: '朗读序章开场',
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      cfg.openingScene.isNotEmpty
                          ? cfg.openingScene
                          : '（由 AI 结合世界观与角色背景动态构思开场剧情）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (cfg.openingScene.isNotEmpty)
                    const AppReadAloudControls(
                        sourceId: 'assembly-preview:opening'),
                  if (cfg.openingOptions.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '初始行动决策分支:',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ...cfg.openingOptions.asMap().entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry.key + 1}. ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                                fontSize: 13,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                entry.value,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
