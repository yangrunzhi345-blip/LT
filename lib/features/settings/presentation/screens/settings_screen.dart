import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../models/llm_provider.dart';
import '../../../../providers/riverpod_providers.dart';
import '../widgets/appearance_section.dart';
import '../widgets/data_management_section.dart';
import '../widgets/model_params_section.dart';
import '../widgets/provider_config_section.dart';

/// 现代化响应式设置中心主界面
/// 基于 Master-Detail 结构重构，提供宽屏专业导航栏、单点返回入口与动态服务状态指示
class SettingsScreen extends ConsumerStatefulWidget {
  final VoidCallback? onMenuPressed;
  final int initialTab;

  const SettingsScreen({
    super.key,
    this.onMenuPressed,
    this.initialTab = 0,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _currentIndex = 0;

  static const _tabs = [
    (
      icon: Icons.dns_rounded,
      label: '模型与 API',
      subtitle: '服务商与密钥配置',
    ),
    (
      icon: Icons.tune_rounded,
      label: '会话参数',
      subtitle: '采样率与深度思考',
    ),
    (
      icon: Icons.palette_rounded,
      label: '主题配色',
      subtitle: '深浅与主题色彩',
    ),
    (
      icon: Icons.storage_rounded,
      label: '数据管理',
      subtitle: 'Token 统计与存储',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab.clamp(0, _tabs.length - 1);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: _currentIndex,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (mounted && _currentIndex != _tabController.index) {
        setState(() => _currentIndex = _tabController.index);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onSelectTab(int index) {
    if (_currentIndex == index) return;
    setState(() => _currentIndex = index);
    _tabController.animateTo(index);
  }

  void _handleReturnHome() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      ref.read(chatProvider).navigateToAdventureHome();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isWide = MediaQuery.of(context).size.width >= 800;
    final chat = ref.watch(chatProvider);
    final settings = chat.settingsProvider;

    final isConfigured = settings.isKeyConfigured;
    final providerName =
        settings.providerType == LLMProvider.deepseek ? 'DeepSeek' : '自定义';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: isDark
            ? colorScheme.surfaceContainerLowest
            : colorScheme.surfaceContainerLow,
        leadingWidth: isWide ? 136 : 56,
        leading: isWide
            ? Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: FilledButton.tonalIcon(
                    onPressed: _handleReturnHome,
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: const Text('返回大厅'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: '返回大厅',
                onPressed: _handleReturnHome,
              ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            const Text(
              '设置中心',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            if (isWide) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  '系统配置',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // 服务连通与在服状态胶囊指示器
          InkWell(
            onTap: () => _onSelectTab(0),
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isConfigured
                    ? (isDark
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.primaryContainer.withValues(alpha: 0.4))
                    : colorScheme.errorContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: isConfigured
                      ? colorScheme.primary.withValues(alpha: 0.4)
                      : colorScheme.error.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isConfigured
                          ? const Color(0xFF22C55E)
                          : colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isConfigured ? '$providerName 官方在服' : '未配置密钥',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isConfigured
                          ? colorScheme.primary
                          : colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: isWide ? AppSpacing.md : AppSpacing.xs),
        ],
        bottom: !isWide
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.4),
                        width: 1,
                      ),
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: colorScheme.primary,
                    unselectedLabelColor: colorScheme.onSurfaceVariant,
                    indicatorColor: colorScheme.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: _tabs
                        .map((t) => Tab(
                              icon: Icon(t.icon, size: 18),
                              text: t.label,
                            ))
                        .toList(),
                  ),
                ),
              )
            : null,
      ),
      body: isWide
          ? Row(
              children: [
                // 现代化 Master 设置分类侧边栏 (240px)
                _SettingsSidebar(
                  tabs: _tabs,
                  selectedIndex: _currentIndex,
                  onSelectTab: _onSelectTab,
                ),
                VerticalDivider(
                  thickness: 1,
                  width: 1,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
                // 右侧 Detail 详情内容区
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: SingleChildScrollView(
                      key: ValueKey(_currentIndex),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.lg,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTabHeader(context, _currentIndex),
                              const SizedBox(height: AppSpacing.lg),
                              _buildSelectedTab(_currentIndex),
                              const SizedBox(height: AppSpacing.xxl),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : TabBarView(
              controller: _tabController,
              children: List.generate(
                _tabs.length,
                (index) => SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTabHeader(context, index),
                      const SizedBox(height: AppSpacing.md),
                      _buildSelectedTab(index),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildTabHeader(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tab = _tabs[index];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(tab.icon, color: colorScheme.primary, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tab.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tab.subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedTab(int index) => switch (index) {
        0 => const ProviderConfigSection(),
        1 => const ModelParamsSection(),
        2 => const AppearanceSection(),
        3 => const DataManagementSection(),
        _ => const SizedBox.shrink(),
      };
}

/// 现代化 Master 设置分类导航面板
class _SettingsSidebar extends StatelessWidget {
  final List<({IconData icon, String label, String subtitle})> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelectTab;

  const _SettingsSidebar({
    required this.tabs,
    required this.selectedIndex,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 240,
      color: isDark
          ? colorScheme.surfaceContainerLowest
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
            child: Text(
              '偏好分类',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              itemCount: tabs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final tab = tabs[index];
                final isSelected = index == selectedIndex;

                return _SettingsNavItem(
                  icon: tab.icon,
                  label: tab.label,
                  subtitle: tab.subtitle,
                  isSelected: isSelected,
                  onTap: () => onSelectTab(index),
                );
              },
            ),
          ),
          // 底部系统引擎小卡片
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '灵境核心引擎',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'SQLite · 本地加密优先',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 侧边栏单个导航项
class _SettingsNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _SettingsNavItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SettingsNavItem> createState() => _SettingsNavItemState();
}

class _SettingsNavItemState extends State<_SettingsNavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = widget.isSelected
        ? (isDark
            ? colorScheme.primary.withValues(alpha: 0.16)
            : colorScheme.primaryContainer.withValues(alpha: 0.55))
        : (_isHovered
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : Colors.transparent);

    final borderColor = widget.isSelected
        ? colorScheme.primary.withValues(alpha: 0.5)
        : Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? colorScheme.primary.withValues(alpha: 0.15)
                      : colorScheme.surfaceContainerHigh.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  widget.icon,
                  size: 18,
                  color: widget.isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: widget.isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.75),
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.isSelected)
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
