import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/ui_foundation.dart';
import '../widgets/assembly_opening_ai.dart';

/// 组装阶段开场剧情与推演配置数据
class AssemblyConfigData {
  final String openingScene;
  final List<String> openingOptions;
  final String customPrompt;
  final String difficulty;

  const AssemblyConfigData({
    required this.openingScene,
    required this.openingOptions,
    this.customPrompt = '',
    this.difficulty = '普通',
  });
}

/// 组装阶段序章与规则配置独立页面 (Assembly Config Page)
///
/// 遵循 R02 UI Foundation 规范：
/// AppPageScaffold + AppFormSection + AppSelect + AppTextField + AppPrimaryButton
/// 支持 320px 窄屏适配与键盘避让。
class AssemblyConfigPage extends StatefulWidget {
  final String? initialOpeningScene;
  final List<String>? initialOptions;
  final String? initialPrompt;
  final String? initialDifficulty;
  final String? worldviewName;
  final String? protagonistName;

  /// Assembly snapshot for the shared AI prologue generator. Null hides the AI
  /// panel, so a host without an adventure context keeps the manual-only page.
  final OpeningAiContext? aiContext;
  final ValueChanged<AssemblyConfigData>? onSave;

  const AssemblyConfigPage({
    super.key,
    this.initialOpeningScene,
    this.initialOptions,
    this.initialPrompt,
    this.initialDifficulty,
    this.worldviewName,
    this.protagonistName,
    this.aiContext,
    this.onSave,
  });

  @override
  State<AssemblyConfigPage> createState() => _AssemblyConfigPageState();
}

class _AssemblyConfigPageState extends State<AssemblyConfigPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _openingSceneCtrl;
  late final TextEditingController _option1Ctrl;
  late final TextEditingController _option2Ctrl;
  late final TextEditingController _option3Ctrl;
  late final TextEditingController _promptCtrl;
  late String _selectedDifficulty;

  static const List<String> _difficultyOptions = [
    '普通 (标准叙事与平衡挑战)',
    '休闲 (注重剧情与轻松沉浸)',
    '困难 (严苛规则与硬核抉择)',
  ];

  @override
  void initState() {
    super.initState();
    _openingSceneCtrl =
        TextEditingController(text: widget.initialOpeningScene ?? '');

    final opts = widget.initialOptions ?? const <String>[];
    _option1Ctrl = TextEditingController(text: opts.isNotEmpty ? opts[0] : '');
    _option2Ctrl = TextEditingController(text: opts.length > 1 ? opts[1] : '');
    _option3Ctrl = TextEditingController(text: opts.length > 2 ? opts[2] : '');

    _promptCtrl = TextEditingController(text: widget.initialPrompt ?? '');
    _selectedDifficulty = widget.initialDifficulty ?? _difficultyOptions.first;
    if (!_difficultyOptions.contains(_selectedDifficulty)) {
      _selectedDifficulty = _difficultyOptions.first;
    }
  }

  @override
  void dispose() {
    _openingSceneCtrl.dispose();
    _option1Ctrl.dispose();
    _option2Ctrl.dispose();
    _option3Ctrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  /// Writes an AI-generated prologue back into the editable fields.
  void _applyGeneratedOpening(OpeningAiOutcome outcome) {
    setState(() {
      if (outcome.scene.isNotEmpty) {
        _openingSceneCtrl.text = outcome.scene;
      }
      if (outcome.options.isNotEmpty) {
        _option1Ctrl.text = outcome.options[0];
        _option2Ctrl.text =
            outcome.options.length > 1 ? outcome.options[1] : '';
        _option3Ctrl.text =
            outcome.options.length > 2 ? outcome.options[2] : '';
      }
    });
  }

  void _handleSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final options = [
      _option1Ctrl.text.trim(),
      _option2Ctrl.text.trim(),
      _option3Ctrl.text.trim(),
    ].where((s) => s.isNotEmpty).toList();

    final data = AssemblyConfigData(
      openingScene: _openingSceneCtrl.text.trim(),
      openingOptions: options,
      customPrompt: _promptCtrl.text.trim(),
      difficulty: _selectedDifficulty,
    );

    if (widget.onSave != null) {
      widget.onSave!(data);
    }
    Navigator.of(context).pop(data);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final subtitleParts = [
      if (widget.worldviewName != null && widget.worldviewName!.isNotEmpty)
        '世界: ${widget.worldviewName}',
      if (widget.protagonistName != null && widget.protagonistName!.isNotEmpty)
        '主角: ${widget.protagonistName}',
    ];

    return AppPageScaffold(
      title: '序章剧情与分支配置',
      titleWidget: subtitleParts.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('序章剧情与分支配置', style: theme.textTheme.titleMedium),
                Text(
                  subtitleParts.join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : null,
      bottomBar: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppPrimaryButton(
                key: const Key('assembly-config-submit-button'),
                label: '保存配置并继续',
                onPressed: _handleSubmit,
              ),
            ],
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.aiContext != null) ...[
                OpeningAiPanel(
                  promptController: _promptCtrl,
                  contextBuilder: () => widget.aiContext!,
                  onGenerated: _applyGeneratedOpening,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AppFormSection(
                title: '开场第一幕剧情',
                description: '设定玩家进入冒险后的第一幕情境描述、遭遇或开篇转折。',
                child: AppTextField(
                  key: const Key('assembly-config-opening-scene-input'),
                  controller: _openingSceneCtrl,
                  hintText: '描述冒险启程时的时刻、环境与突发危机...',
                  maxLines: 5,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '请输入开场剧情设定';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormSection(
                title: '初始行动抉择分支 (可选)',
                description: '供玩家在开局时做出的三个行动分支，若留空将在进入后由 AI 动态生成。',
                child: Column(
                  children: [
                    AppTextField(
                      key: const Key('assembly-config-option-1-input'),
                      controller: _option1Ctrl,
                      label: '抉择分支 1',
                      hintText: '例如：拔剑迎击袭来的黑影',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      key: const Key('assembly-config-option-2-input'),
                      controller: _option2Ctrl,
                      label: '抉择分支 2',
                      hintText: '例如：寻找掩体并呼唤同伴掩护',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      key: const Key('assembly-config-option-3-input'),
                      controller: _option3Ctrl,
                      label: '抉择分支 3',
                      hintText: '例如：仔细观察四周环境寻找逃生通道',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppFormSection(
                title: '推演难度与自定义指引',
                description: '控制游戏运行的难度倾向与自定义提示词。',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppSelect<String>(
                      label: '叙事难度',
                      value: _selectedDifficulty,
                      items: _difficultyOptions
                          .map((opt) => AppSelectItem(value: opt, label: opt))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedDifficulty = val);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      key: const Key('assembly-config-prompt-input'),
                      controller: _promptCtrl,
                      label: '自定义引导提示词 (可选)',
                      hintText: '例如：侧重悬疑侦探氛围、多增加环境感官细节描摹...',
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
