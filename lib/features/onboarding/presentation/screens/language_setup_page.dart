import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/localization/app_locale.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../providers/riverpod_providers.dart';

/// 首次启动独立语言选择页面
///
/// 遵循 Navigation-first 原则，以独立全屏形式呈现（绝不使用 Dialog / BottomSheet）。
/// 语言名称始终以其母语原生显示：
/// - English
/// - 简体中文
/// - 繁體中文
/// - 日本語
/// - 한국어
///
/// 初始状态下根据系统语言自动推荐并高亮，用户主动确认后持久化并完成热切换。
class LanguageSetupPage extends ConsumerStatefulWidget {
  const LanguageSetupPage({
    super.key,
    required this.onConfirmed,
  });

  /// 用户完成语言确认后的回调
  final Future<void> Function() onConfirmed;

  @override
  ConsumerState<LanguageSetupPage> createState() => _LanguageSetupPageState();
}

class _LanguageSetupPageState extends ConsumerState<LanguageSetupPage> {
  late AppLocale _selectedLocale;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // 初始高亮取当前 controller 预解析的推荐语言（系统支持则匹配系统，否则为 English）
    final controller = ref.read(appLocaleControllerProvider);
    _selectedLocale = controller.currentLocale;
  }

  Future<void> _handleConfirm() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final controller = ref.read(appLocaleControllerProvider);
      await controller.setLocale(_selectedLocale, isFirstRunSetup: true);
      if (!mounted) return;
      await widget.onConfirmed();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),

                  // 顶部品牌 Logo
                  Center(
                    child: Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.translate_rounded,
                        size: 32,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // 标题与副标题（多语言引导）
                  Text(
                    _titleForLocale(_selectedLocale),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _subtitleForLocale(_selectedLocale),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // 5 种支持语言列表卡片
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: AppLocale.values.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.25),
                      ),
                      itemBuilder: (context, index) {
                        final localeOption = AppLocale.values[index];
                        final isSelected = localeOption == _selectedLocale;

                        return InkWell(
                          onTap: () {
                            setState(() => _selectedLocale = localeOption);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        localeOption.nativeName,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? scheme.primary
                                              : scheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _englishSubLabel(localeOption),
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? scheme.primary
                                          : scheme.outlineVariant,
                                      width: isSelected ? 2 : 1.5,
                                    ),
                                    color: isSelected
                                        ? scheme.primary
                                        : Colors.transparent,
                                  ),
                                  child: isSelected
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: scheme.onPrimary,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const Spacer(),

                  // 底部确认按钮
                  FilledButton(
                    onPressed: _isSaving ? null : _handleConfirm,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _confirmLabelForLocale(_selectedLocale),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _titleForLocale(AppLocale locale) {
    return switch (locale) {
      AppLocale.en => 'Choose Language',
      AppLocale.zhHans => '选择语言',
      AppLocale.zhHant => '選擇語言',
      AppLocale.ja => '言語を選択',
      AppLocale.ko => '언어 선택',
    };
  }

  String _subtitleForLocale(AppLocale locale) {
    return switch (locale) {
      AppLocale.en => 'Please select your preferred application language',
      AppLocale.zhHans => '请选择应用显示语言',
      AppLocale.zhHant => '請選擇應用程式顯示語言',
      AppLocale.ja => 'アプリケーションの表示言語を選択してください',
      AppLocale.ko => '애플리케이션 표시 언어를 선택해 주세요',
    };
  }

  String _confirmLabelForLocale(AppLocale locale) {
    return switch (locale) {
      AppLocale.en => 'Continue',
      AppLocale.zhHans => '确认并继续',
      AppLocale.zhHant => '確認並繼續',
      AppLocale.ja => '確定して次へ',
      AppLocale.ko => '확인 및 계속',
    };
  }

  String _englishSubLabel(AppLocale locale) {
    return switch (locale) {
      AppLocale.en => 'English',
      AppLocale.zhHans => 'Simplified Chinese',
      AppLocale.zhHant => 'Traditional Chinese',
      AppLocale.ja => 'Japanese',
      AppLocale.ko => 'Korean',
    };
  }
}
