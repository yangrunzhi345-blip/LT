import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../core/theme/app_colors.dart';
import '../core/feedback/app_feedback.dart';
import '../core/theme/app_spacing.dart';
import '../core/widgets/narr_aitor_dropdown.dart';
import '../models/completion_params.dart';
import '../providers/riverpod_providers.dart';
import '../models/llm_provider.dart';
import '../services/translation_service.dart';
import '../widgets/narr_aitor_loading.dart';
import '../core/refresh/page_refresh_scope.dart';

class SettingsCenterScreen extends ConsumerStatefulWidget {
  final VoidCallback? onMenuPressed;

  const SettingsCenterScreen({super.key, this.onMenuPressed});

  @override
  ConsumerState<SettingsCenterScreen> createState() =>
      _SettingsCenterScreenState();
}

enum _SettingsSection { model, params, theme, tts, token }

class _SettingsCenterScreenState extends ConsumerState<SettingsCenterScreen> {
  _SettingsSection _section = _SettingsSection.model;

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(chatProvider);
    return PageRefreshScope(
      onRefresh: () async {
        await ref.read(chatProvider).settingsProvider.loadApiKey();
        return const PageRefreshResult.success();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: widget.onMenuPressed == null
              ? null
              : IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: '菜单',
                  onPressed: widget.onMenuPressed,
                ),
          title: const Text('设置中心'),
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            final content = _buildContent(provider);
            if (compact) {
              return ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _SettingsNavigation(
                    selected: _section,
                    compact: true,
                    onSelected: (value) => setState(() => _section = value),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  content,
                ],
              );
            }
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 246,
                    child: _SettingsNavigation(
                      selected: _section,
                      onSelected: (value) => setState(() => _section = value),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(child: content),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(dynamic provider) {
    return switch (_section) {
      _SettingsSection.model => _ModelApiPanel(provider: provider),
      _SettingsSection.params => _ParamsPanel(provider: provider),
      _SettingsSection.theme => _ThemePanel(provider: provider),
      _SettingsSection.tts => _TtsTranslationPanel(provider: provider),
      _SettingsSection.token => _TokenPanel(provider: provider),
    };
  }
}

class _SettingsNavigation extends StatelessWidget {
  final _SettingsSection selected;
  final ValueChanged<_SettingsSection> onSelected;
  final bool compact;

  const _SettingsNavigation({
    required this.selected,
    required this.onSelected,
    this.compact = false,
  });

  static const _items = [
    (
      section: _SettingsSection.model,
      icon: Icons.smart_toy_outlined,
      title: '模型与 API',
      hint: '服务商与密钥'
    ),
    (
      section: _SettingsSection.params,
      icon: Icons.tune_rounded,
      title: '会话参数',
      hint: '生成与上下文'
    ),
    (
      section: _SettingsSection.theme,
      icon: Icons.palette_outlined,
      title: '主题配色',
      hint: '外观与字体'
    ),
    (
      section: _SettingsSection.tts,
      icon: Icons.record_voice_over_outlined,
      title: '语音与翻译',
      hint: 'TTS 与消息翻译'
    ),
    (
      section: _SettingsSection.token,
      icon: Icons.data_usage_rounded,
      title: 'Token 用量',
      hint: '用量与组成'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final items = _items
        .map(
          (item) => _NavigationItem(
            icon: item.icon,
            title: item.title,
            hint: item.hint,
            selected: selected == item.section,
            compact: compact,
            onTap: () => onSelected(item.section),
          ),
        )
        .toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: compact
            ? Wrap(spacing: 6, runSpacing: 6, children: items)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 10, 12, 16),
                    child: Row(
                      children: [
                        Icon(Icons.settings_outlined, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('应用设置',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w800)),
                              SizedBox(height: 2),
                              Text('模型、会话、主题与用量',
                                  style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...items,
                ],
              ),
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _NavigationItem({
    required this.icon,
    required this.title,
    required this.hint,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      width: compact ? 210 : null,
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(hint, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (!compact)
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: color.withValues(alpha: .7)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final Widget child;
  final Widget? footer;

  const _Panel({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
    this.badge,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final body =
              constraints.maxHeight.isFinite ? Expanded(child: child) : child;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .12),
                      child: Icon(icon,
                          size: 21,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 3),
                          Text(description,
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (badge != null) Chip(label: Text(badge!)),
                  ],
                ),
              ),
              const Divider(height: 1),
              body,
              if (footer != null) ...[
                const Divider(height: 1),
                footer!,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ModelApiPanel extends StatefulWidget {
  final dynamic provider;

  const _ModelApiPanel({required this.provider});

  @override
  State<_ModelApiPanel> createState() => _ModelApiPanelState();
}

class _ModelApiPanelState extends State<_ModelApiPanel> {
  late LLMProvider _selectedProvider;
  late String _selectedModel;
  late TextEditingController _keyController;
  late TextEditingController _endpointController;
  late TextEditingController _modelController;
  late _ProviderRegion _selectedRegion;
  late final Map<LLMProvider, String> _draftKeys;
  late final Map<LLMProvider, String> _draftEndpoints;
  late final Map<LLMProvider, String> _draftModels;
  bool _obscureKey = true;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _selectedProvider = widget.provider.providerType;
    _selectedModel = widget.provider.modelName;
    _selectedRegion = _regionForProvider(_selectedProvider);
    _draftKeys = {
      for (final p in LLMProvider.values)
        p: widget.provider.getProviderKey(p) ?? ''
    };
    _draftEndpoints = {
      for (final p in LLMProvider.values)
        p: widget.provider.getProviderBaseUrl(p),
    };
    _draftModels = {
      for (final p in LLMProvider.values)
        p: widget.provider.getProviderModel(p) ?? '',
    };
    _draftEndpoints[_selectedProvider] =
        widget.provider.getProviderBaseUrl(_selectedProvider);
    _draftModels[_selectedProvider] = _selectedModel;
    _keyController =
        TextEditingController(text: _draftKeys[_selectedProvider] ?? '');
    _endpointController = TextEditingController(
      text: _draftEndpoints[_selectedProvider] ??
          _selectedProvider.defaultBaseUrl,
    );
    _modelController = TextEditingController(
        text: _draftModels[_selectedProvider] ?? _selectedModel);
    _normalizeSelection();
  }

  void _normalizeSelection() {
    if (_selectedProvider == LLMProvider.custom) {
      _selectedModel = _modelController.text.trim();
    } else if (!_selectedProvider.availableModels.contains(_selectedModel)) {
      _selectedModel = _selectedProvider.defaultModel;
      _modelController.text = _selectedModel;
    }
    if (_endpointController.text.isEmpty) {
      _endpointController.text = _selectedProvider.defaultBaseUrl;
    }
  }

  @override
  void dispose() {
    _keyController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _captureDraftForCurrentProvider() {
    _draftKeys[_selectedProvider] = _keyController.text;
    _draftEndpoints[_selectedProvider] = _endpointController.text;
    _draftModels[_selectedProvider] = _modelController.text;
  }

  void _selectProvider(LLMProvider provider) {
    setState(() {
      _captureDraftForCurrentProvider();
      _selectedProvider = provider;
      _selectedRegion = _regionForProvider(provider);
      final savedModel = _draftModels[provider] ?? '';
      _selectedModel = provider.availableModels.contains(savedModel)
          ? savedModel
          : (provider.availableModels.contains(provider.defaultModel)
              ? provider.defaultModel
              : savedModel);
      _keyController.text = _draftKeys[provider] ?? '';
      _endpointController.text = provider == LLMProvider.custom
          ? (_draftEndpoints[provider] ?? provider.defaultBaseUrl)
          : provider.defaultBaseUrl;
      _modelController.text = _selectedModel;
      _testResult = null;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final ok = await ProviderScope.containerOf(context, listen: false)
          .read(modelSettingsControllerProvider)
          .testConnection(
            provider: _selectedProvider,
            apiKey: _keyController.text.trim(),
            model: _selectedProvider == LLMProvider.custom
                ? _modelController.text.trim()
                : _selectedModel,
            endpoint: _endpointController.text.trim(),
          );
      if (mounted) setState(() => _testResult = ok ? '连接成功' : '连接失败');
    } catch (error) {
      if (mounted) {
        setState(() => _testResult = error.toString().split('\n').first);
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final provider = widget.provider;
    _captureDraftForCurrentProvider();
    final effectiveModel = _selectedProvider == LLMProvider.custom
        ? _modelController.text.trim()
        : _selectedModel;
    await provider.setProvider(_selectedProvider);
    await provider.setApiBaseUrl(_endpointController.text);
    await provider.setApiKey(_keyController.text);
    if (effectiveModel.isNotEmpty) {
      await provider.setModel(effectiveModel);
    }
    if (mounted) setState(() => _testResult = '配置已保存');
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    return _Panel(
      icon: Icons.smart_toy_outlined,
      title: '模型与 API',
      description: '选择服务商、模型并配置连接信息',
      badge: _selectedProvider.displayName,
      footer: _PanelFooter(
        leading: OutlinedButton.icon(
          onPressed: _testing ? null : _testConnection,
          icon: _testing
              ? const SizedBox(
                  width: 16, height: 16, child: NarrAItorLoading.mini(size: 16))
              : const Icon(Icons.wifi_rounded),
          label: Text(_testing ? '测试中' : '测试连接'),
        ),
        action: FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('保存配置'),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RegionSegmentedControl(
              selectedRegion: _selectedRegion,
              onChanged: (region) {
                final target = _providersForRegion(region);
                if (target.isNotEmpty && !target.contains(_selectedProvider)) {
                  _selectProvider(target.first);
                } else {
                  setState(() => _selectedRegion = region);
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
            _ProviderOptionList(
              options: _providerOptionsFor(_selectedRegion),
              selectedProvider: _selectedProvider,
              onSelected: _selectProvider,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.lg),
            if (_selectedProvider != LLMProvider.custom) ...[
              const _SettingsHeading(
                title: '模型',
                description: '选择当前服务商提供的模型',
              ),
              NarrAItorDropdown<String>(
                value: _selectedModel.isEmpty ? null : _selectedModel,
                hintText: _selectedProvider.defaultModel,
                options: _selectedProvider.availableModels
                    .map((model) => NarrAItorDropdownOption(
                          value: model,
                          label: model,
                          subtitle: model == _selectedProvider.defaultModel
                              ? '推荐模型'
                              : null,
                          leading: Icon(
                            model == _selectedProvider.defaultModel
                                ? Icons.star_outline
                                : Icons.memory,
                            size: 16,
                          ),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedModel = value;
                    _modelController.text = value;
                    _captureDraftForCurrentProvider();
                  });
                },
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            _SettingsHeading(
              title: 'API Key',
              description: '密钥会加密保存到本地数据库',
              trailing: Text(
                _keyController.text.trim().isEmpty ? '未设置' : '已设置',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF4B73FF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextField(
              controller: _keyController,
              obscureText: _obscureKey,
              onChanged: (_) => _captureDraftForCurrentProvider(),
              decoration: _settingsFieldDecoration(
                context,
                hintText: 'sk-...',
                suffixIcon: IconButton(
                  tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                  icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureKey = !_obscureKey),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _SettingsHeading(
              title: 'API 端点',
              description: _selectedProvider == LLMProvider.custom
                  ? '可编辑'
                  : '官方端点，内置服务商不可修改',
            ),
            TextField(
              controller: _endpointController,
              readOnly: _selectedProvider != LLMProvider.custom,
              onChanged: _selectedProvider == LLMProvider.custom
                  ? (_) => _captureDraftForCurrentProvider()
                  : null,
              decoration: _settingsFieldDecoration(
                context,
                hintText: _selectedProvider.defaultBaseUrl.isEmpty
                    ? 'https://...'
                    : _selectedProvider.defaultBaseUrl,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _endpointController.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制 API 端点'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_selectedProvider == LLMProvider.custom) ...[
              const SizedBox(height: AppSpacing.lg),
              const _SettingsHeading(
                title: '模型标识',
                description: '自定义兼容接口需要手动填写模型名',
              ),
              TextField(
                controller: _modelController,
                onChanged: (value) {
                  _selectedModel = value;
                  _captureDraftForCurrentProvider();
                },
                decoration: _settingsFieldDecoration(
                  context,
                  hintText: 'gpt-4.1-mini / claude-sonnet-5',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: _modelController.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制模型标识'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
            if (_testResult != null) ...[
              const SizedBox(height: 12),
              Text(_testResult!,
                  style: TextStyle(
                      color: _testResult == '连接成功'
                          ? AppColors.success
                          : Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
                '当前状态：${provider.isKeyConfigured ? '已配置 API Key' : '尚未配置 API Key'}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

enum _ProviderRegion { domestic, overseas, custom }

_ProviderRegion _regionForProvider(LLMProvider provider) {
  return switch (provider) {
    LLMProvider.custom => _ProviderRegion.custom,
    _ when LLMProvider.domesticProviders.contains(provider) =>
      _ProviderRegion.domestic,
    _ => _ProviderRegion.overseas,
  };
}

List<LLMProvider> _providersForRegion(_ProviderRegion region) {
  return switch (region) {
    _ProviderRegion.domestic => LLMProvider.domesticProviders,
    _ProviderRegion.overseas => LLMProvider.overseasProviders,
    _ProviderRegion.custom => const [LLMProvider.custom],
  };
}

List<_ProviderOption> _providerOptionsFor(_ProviderRegion region) {
  return switch (region) {
    _ProviderRegion.domestic => const [
        _ProviderOption('DeepSeek', provider: LLMProvider.deepseek),
        _ProviderOption('通义千问（Qwen）', provider: LLMProvider.qwen),
        _ProviderOption('智谱 GLM', provider: LLMProvider.zhipu),
        _ProviderOption('Kimi（月之暗面）', provider: LLMProvider.kimi),
        _ProviderOption('豆包（字节）', provider: LLMProvider.doubao),
        _ProviderOption('百度文心', provider: LLMProvider.baidu),
        _ProviderOption('MiniMax', provider: LLMProvider.minimax),
        _ProviderOption('讯飞星火', provider: LLMProvider.xunfei),
      ],
    _ProviderRegion.overseas => const [
        _ProviderOption('OpenAI', provider: LLMProvider.openai),
        _ProviderOption('Claude（Anthropic）', provider: LLMProvider.anthropic),
        _ProviderOption('Google Gemini', provider: LLMProvider.gemini),
      ],
    _ProviderRegion.custom => const [
        _ProviderOption('自定义兼容接口', provider: LLMProvider.custom),
      ],
  };
}

class _RegionSegmentedControl extends StatelessWidget {
  final _ProviderRegion selectedRegion;
  final ValueChanged<_ProviderRegion> onChanged;

  const _RegionSegmentedControl({
    required this.selectedRegion,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFE1E1E1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _tab(context, _ProviderRegion.domestic, '国内'),
          _tab(context, _ProviderRegion.overseas, '海外'),
          _tab(context, _ProviderRegion.custom, '自定义'),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, _ProviderRegion region, String label) {
    final selected = selectedRegion == region;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(region),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? (isDark ? AppColors.darkSurfaceElevated : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected
                  ? const Color(0xFF4B73FF)
                  : (isDark ? Colors.white54 : const Color(0xFF6F7D92)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProviderOption {
  final String title;
  final LLMProvider provider;

  const _ProviderOption(this.title, {required this.provider});
}

class _ProviderOptionList extends StatelessWidget {
  final List<_ProviderOption> options;
  final LLMProvider selectedProvider;
  final ValueChanged<LLMProvider> onSelected;

  const _ProviderOptionList({
    required this.options,
    required this.selectedProvider,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: options
          .map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ProviderOptionTile(
                option: option,
                selected: option.provider == selectedProvider,
                onTap: () => onSelected(option.provider),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ProviderOptionTile extends StatelessWidget {
  final _ProviderOption option;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF4B73FF);
    final textColor = selected
        ? accent
        : (isDark ? const Color(0xFFF1F5F9) : const Color(0xFF6F7D92));
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurfaceElevated.withValues(alpha: 0.72)
              : Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : const Color(0xFFE5EAF2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected ? accent : const Color(0xFF9AA6B8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                option.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _settingsFieldDecoration(
  BuildContext context, {
  required String hintText,
  Widget? suffixIcon,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.70),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.2)
              : const Color(0xFFE5EAF2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.2)
              : const Color(0xFFE5EAF2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF4B73FF)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    isDense: true,
    suffixIcon: suffixIcon,
  );
}

class _SettingsHeading extends StatelessWidget {
  final String title;
  final String description;
  final Widget? trailing;

  const _SettingsHeading({
    required this.title,
    required this.description,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(description, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _ParamsPanel extends StatefulWidget {
  final dynamic provider;

  const _ParamsPanel({required this.provider});

  @override
  State<_ParamsPanel> createState() => _ParamsPanelState();
}

class _ParamsPanelState extends State<_ParamsPanel> {
  late CompletionParams _params;

  @override
  void initState() {
    super.initState();
    _params = widget.provider.completionParams;
  }

  String _presetName() {
    for (final entry in CompletionParams.presets.entries) {
      if (entry.value == _params) return entry.key;
    }
    return '自定义';
  }

  void _applyPreset(String name) {
    final preset = CompletionParams.presets[name];
    if (preset != null) setState(() => _params = preset);
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      icon: Icons.tune_rounded,
      title: '会话参数',
      description: '调整生成策略与单次回复上限',
      badge: _presetName(),
      footer: _PanelFooter(
        leading: TextButton(
          onPressed: () => _applyPreset('剧情模式'),
          child: const Text('恢复剧情预设'),
        ),
        action: FilledButton.icon(
          onPressed: () async {
            await widget.provider.setCompletionParams(_params);
            if (context.mounted) AppFeedback.success(context, '会话参数已应用');
          },
          icon: const Icon(Icons.check_rounded),
          label: const Text('应用参数'),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeading('参数预设', '选择预设后仍可继续微调单项参数'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...CompletionParams.presets.keys.map((name) => ChoiceChip(
                      label: Text(name),
                      selected: _presetName() == name,
                      onSelected: (_) => _applyPreset(name),
                    )),
                ChoiceChip(
                  label: const Text('自定义'),
                  selected: _presetName() == '自定义',
                  onSelected: (_) {},
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionHeading('生成参数', '参数会应用到后续模型请求'),
            _ParamSlider(
              label: 'Temperature',
              description: '控制回复的随机性与创造性',
              value: _params.temperature,
              min: 0,
              max: 2,
              onChanged: (value) => setState(
                  () => _params = _params.copyWith(temperature: value)),
            ),
            _ParamSlider(
              label: 'Top-P',
              description: '控制候选词的累计概率范围',
              value: _params.topP,
              min: 0,
              max: 1,
              onChanged: (value) =>
                  setState(() => _params = _params.copyWith(topP: value)),
            ),
            _ParamSlider(
              label: '频率惩罚',
              description: '降低重复词语和句式出现频率',
              value: _params.frequencyPenalty,
              min: -2,
              max: 2,
              onChanged: (value) => setState(
                  () => _params = _params.copyWith(frequencyPenalty: value)),
            ),
            _ParamSlider(
              label: '存在惩罚',
              description: '鼓励模型引入尚未出现的新内容',
              value: _params.presencePenalty,
              min: -2,
              max: 2,
              onChanged: (value) => setState(
                  () => _params = _params.copyWith(presencePenalty: value)),
            ),
            _ParamSlider(
              label: 'Max Tokens',
              description: '限制单次回复可生成的最大 Token 数',
              value: _params.maxTokens.toDouble(),
              min: 1024,
              max: 32768,
              divisions: 31,
              valueLabel: _params.maxTokens.toString(),
              onChanged: (value) => setState(
                  () => _params = _params.copyWith(maxTokens: value.round())),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemePanel extends StatelessWidget {
  final dynamic provider;

  const _ThemePanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final currentName = AppColors.colorSeeds.entries
            .where((entry) => entry.value == provider.colorSeed)
            .map((entry) => entry.key)
            .firstOrNull ??
        '海洋蓝';
    return _Panel(
      icon: Icons.palette_outlined,
      title: '主题配色',
      description: '主题、明暗外观与对话字体集中管理',
      badge: currentName,
      footer: _PanelFooter(
        leading: TextButton(
          onPressed: provider.resetTheme,
          child: const Text('恢复默认主题'),
        ),
        action: const Text(
          '✓ 已即时应用',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeading('外观模式', '切换后立即应用到整个应用'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ThemeModeChip(
                    provider: provider,
                    mode: ThemeMode.light,
                    label: '浅色模式',
                    icon: Icons.light_mode_outlined),
                _ThemeModeChip(
                    provider: provider,
                    mode: ThemeMode.dark,
                    label: '暗色模式',
                    icon: Icons.dark_mode_outlined),
                _ThemeModeChip(
                    provider: provider,
                    mode: ThemeMode.system,
                    label: '跟随系统',
                    icon: Icons.brightness_auto_outlined),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionHeading('主题主色', '主按钮、选中状态和强调元素同步变化'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: AppColors.colorSeeds.entries.map((entry) {
                final selected = entry.key == currentName;
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => provider.setColorSeed(entry.value),
                  child: Container(
                    width: 112,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? entry.value
                            : Theme.of(context).dividerColor,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 9, backgroundColor: entry.value),
                        const SizedBox(width: 7),
                        Expanded(
                            child: Text(entry.key,
                                overflow: TextOverflow.ellipsis)),
                        if (selected)
                          Icon(Icons.check, size: 16, color: entry.value),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionHeading('对话字体大小', '只影响聊天正文，不改变系统控件可读性'),
            Slider(
              value: provider.chatFontSize,
              min: 12,
              max: 20,
              divisions: 8,
              label: '${provider.chatFontSize.toInt()}',
              onChanged: (value) => provider.setChatFontSize(value),
            ),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('A 小'), Text('标准'), Text('A 大')],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModeChip extends StatelessWidget {
  final dynamic provider;
  final ThemeMode mode;
  final String label;
  final IconData icon;

  const _ThemeModeChip({
    required this.provider,
    required this.mode,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: provider.themeMode == mode,
      onSelected: (_) => provider.updateThemeMode(mode),
    );
  }
}

/// 语音（TTS）与翻译开关面板。
///
/// TTS/翻译状态由 SettingsProvider 持有的服务管理（内存态），
/// 面板以局部状态呈现并即时写入。
class _TtsTranslationPanel extends StatefulWidget {
  final dynamic provider;

  const _TtsTranslationPanel({required this.provider});

  @override
  State<_TtsTranslationPanel> createState() => _TtsTranslationPanelState();
}

class _TtsTranslationPanelState extends State<_TtsTranslationPanel> {
  late bool _enabled = widget.provider.tts.enabled;
  late bool _autoRead = widget.provider.tts.autoRead;
  late double _rate = widget.provider.tts.rate;
  late double _pitch = widget.provider.tts.pitch;
  late TranslationMode _mode = widget.provider.translator.mode;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      icon: Icons.record_voice_over_outlined,
      title: '语音与翻译',
      description: '消息朗读（TTS）与对话翻译开关',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeading('消息朗读（TTS）', '启用后可在消息菜单中朗读，自动朗读需模型支持'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用朗读'),
              subtitle: const Text('关闭后消息菜单中的朗读按钮不可用'),
              value: _enabled,
              onChanged: (value) {
                widget.provider.tts.setEnabled(value);
                setState(() => _enabled = value);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动朗读 AI 消息'),
              subtitle: const Text('AI 消息完成后自动朗读'),
              value: _autoRead,
              onChanged: (value) {
                widget.provider.tts.setAutoRead(value);
                setState(() => _autoRead = value);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _SliderRow(
              label: '语速',
              value: _rate,
              min: 0.25,
              max: 2.0,
              display: _rate.toStringAsFixed(2),
              onChanged: (value) {
                widget.provider.tts.setRate(value);
                setState(() => _rate = value);
              },
            ),
            _SliderRow(
              label: '音调',
              value: _pitch,
              min: 0.5,
              max: 2.0,
              display: _pitch.toStringAsFixed(2),
              onChanged: (value) {
                widget.provider.tts.setPitch(value);
                setState(() => _pitch = value);
              },
            ),
            const Divider(height: 32),
            const _SectionHeading('消息翻译', '将对话内容在输入与输出之间翻译'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TranslationModeChip(
                  mode: TranslationMode.off,
                  label: '关闭',
                  icon: Icons.translate,
                  selected: _mode == TranslationMode.off,
                  onTap: () => _selectMode(TranslationMode.off),
                ),
                _TranslationModeChip(
                  mode: TranslationMode.inputOnly,
                  label: '翻译输入',
                  icon: Icons.input,
                  selected: _mode == TranslationMode.inputOnly,
                  onTap: () => _selectMode(TranslationMode.inputOnly),
                ),
                _TranslationModeChip(
                  mode: TranslationMode.outputOnly,
                  label: '翻译输出',
                  icon: Icons.output,
                  selected: _mode == TranslationMode.outputOnly,
                  onTap: () => _selectMode(TranslationMode.outputOnly),
                ),
                _TranslationModeChip(
                  mode: TranslationMode.bidirectional,
                  label: '双向翻译',
                  icon: Icons.swap_horiz,
                  selected: _mode == TranslationMode.bidirectional,
                  onTap: () => _selectMode(TranslationMode.bidirectional),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
                '当前语言：${widget.provider.translator.inputLang} → '
                '${widget.provider.translator.outputLang}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  void _selectMode(TranslationMode mode) {
    widget.provider.translator.setMode(mode);
    setState(() => _mode = mode);
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      SizedBox(
          width: 56,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
      SizedBox(
          width: 48,
          child: Text(display,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall)),
    ]);
  }
}

class _TranslationModeChip extends StatelessWidget {
  final TranslationMode mode;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TranslationModeChip({
    required this.mode,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _TokenPanel extends StatelessWidget {
  final dynamic provider;

  const _TokenPanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final summary = provider.getTokenSummary() as Map<String, dynamic>;
    final modelUsage =
        (summary['modelUsage'] as Map?)?.cast<String, int>() ?? {};
    final session = summary['sessionTokens'] as int? ?? 0;
    final total = summary['totalTokens'] as int? ?? 0;
    final ratio = (session / 1000000).clamp(0.0, 1.0);
    return _Panel(
      icon: Icons.data_usage_rounded,
      title: 'Token 用量',
      description: '查看当前会话和本地累计 Token 统计',
      badge: '${(ratio * 100).toStringAsFixed(2)}%',
      footer: const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text('Token 为本地估算，不代表服务商实际计费。'),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatCard(label: '本次会话', value: '$session', suffix: 'tokens'),
                _StatCard(label: '累计总量', value: '$total', suffix: 'tokens'),
                _StatCard(
                    label: '平均/条',
                    value: '${summary['avgPerMessage'] ?? 0}',
                    suffix: 'tokens/条'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionHeading('上下文窗口状态', '达到 80% 时提示接近上限；当前为本地估算'),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: ratio, minHeight: 10),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionHeading('按模型统计', '统计从当前应用启动后开始记录'),
            if (modelUsage.isEmpty)
              const Text('暂无 Token 记录')
            else
              ...modelUsage.entries.map((entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.smart_toy_outlined),
                    title: Text(entry.key),
                    trailing: Text('${entry.value} tokens'),
                  )),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String suffix;

  const _StatCard(
      {required this.label, required this.value, required this.suffix});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 150),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 5),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(suffix, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PanelFooter extends StatelessWidget {
  final Widget leading;
  final Widget action;

  const _PanelFooter({required this.leading, required this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [leading, action],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String title;
  final String description;

  const _SectionHeading(this.title, this.description);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ParamSlider extends StatelessWidget {
  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? valueLabel;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    final display = valueLabel ?? value.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              Chip(label: Text(display)),
            ],
          ),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
