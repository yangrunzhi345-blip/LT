import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/theme/app_borders.dart';
import 'package:lt_dialogue/core/theme/app_colors.dart';
import 'package:lt_dialogue/core/theme/app_dimensions.dart';
import 'package:lt_dialogue/core/theme/app_radius.dart';
import 'package:lt_dialogue/core/theme/app_shadows.dart';
import 'package:lt_dialogue/core/theme/app_spacing.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/ui_foundation.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestApp({
    required Widget home,
    ThemeMode themeMode = ThemeMode.light,
    double textScaleFactor = 1.0,
    EdgeInsets viewInsets = EdgeInsets.zero,
  }) {
    return MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScaleFactor),
          viewInsets: viewInsets,
        ),
        child: home,
      ),
    );
  }

  group('Phase 1 - Design Tokens & Theme', () {
    test('AppColors divider tokens and context-aware dividerColor', () {
      expect(AppColors.divider, const Color(0x14000000));
      expect(AppColors.darkDivider, const Color(0x14FFFFFF));
    });

    test('AppSpacing edgeInsets helpers match values', () {
      expect(AppSpacing.edgeInsetsXs, const EdgeInsets.all(4));
      expect(AppSpacing.edgeInsetsSm, const EdgeInsets.all(8));
      expect(AppSpacing.edgeInsetsMd, const EdgeInsets.all(12));
      expect(AppSpacing.edgeInsetsLg, const EdgeInsets.all(16));
      expect(AppSpacing.edgeInsetsXl, const EdgeInsets.all(24));
      expect(AppSpacing.edgeInsetsXxl, const EdgeInsets.all(32));
    });

    test('AppRadius control and container tokens', () {
      expect(AppRadius.control, 10.0);
      expect(AppRadius.container, 14.0);
      expect(AppRadius.borderControl.topLeft.x, 10.0);
      expect(AppRadius.borderContainer.topLeft.x, 14.0);
    });

    test('AppDimensions control heights and width limits', () {
      expect(AppDimensions.controlHeightSm, 32.0);
      expect(AppDimensions.controlHeightMd, 40.0);
      expect(AppDimensions.controlHeightLg, 48.0);
      expect(AppDimensions.maxContentWidth, 840.0);
      expect(AppDimensions.maxFormWidth, 640.0);
      expect(AppDimensions.maxNarrativeWidth, 760.0);
      expect(AppDimensions.minSupportedWidth, 320.0);
    });

    testWidgets('AppBorders and AppShadows adapt to theme brightness',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          themeMode: ThemeMode.dark,
          home: Builder(
            builder: (context) {
              final dividerColor = AppBorders.dividerColor(context);
              final dividerSide = AppBorders.dividerSide(context);
              final subtleShadow = AppShadows.subtle(context);
              final elevatedShadow = AppShadows.elevated(context);
              final dialogShadow = AppShadows.dialog(context);

              expect(dividerColor, AppColors.darkDivider);
              expect(dividerSide.color, AppColors.darkDivider);
              expect(dividerSide.width, 1.0);
              expect(subtleShadow.isNotEmpty, isTrue);
              expect(elevatedShadow.isNotEmpty, isTrue);
              expect(dialogShadow.isNotEmpty, isTrue);

              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });

    test('AppTheme includes dividerTheme and textButtonTheme', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();

      expect(light.dividerTheme.color, AppColors.divider);
      expect(dark.dividerTheme.color, AppColors.darkDivider);
      expect(light.dividerTheme.thickness, 1.0);
      expect(dark.dividerTheme.thickness, 1.0);

      expect(light.textButtonTheme.style, isNotNull);
      expect(dark.textButtonTheme.style, isNotNull);
    });
  });

  group('Phase 1 - Buttons & Responsive Action Bar', () {
    testWidgets('AppActionButton.text and quiet variant trigger click',
        (tester) async {
      bool textClicked = false;
      bool quietClicked = false;

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Row(
              children: [
                AppActionButton.text(
                  label: '文本按钮',
                  onPressed: () => textClicked = true,
                ),
                AppActionButton.quiet(
                  label: '安静按钮',
                  onPressed: () => quietClicked = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('文本按钮'), findsOneWidget);
      expect(find.text('安静按钮'), findsOneWidget);

      await tester.tap(find.text('文本按钮'));
      await tester.pump();
      expect(textClicked, isTrue);

      await tester.tap(find.text('安静按钮'));
      await tester.pump();
      expect(quietClicked, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppTextButton handles sizes and loading state',
        (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          home: const Scaffold(
            body: Column(
              children: [
                AppTextButton(
                  label: '小号文本按钮',
                  size: AppButtonSize.small,
                ),
                AppTextButton(
                  label: '中号文本按钮',
                  size: AppButtonSize.medium,
                ),
                AppTextButton(
                  label: '大号文本按钮',
                  size: AppButtonSize.large,
                  isLoading: true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('小号文本按钮'), findsOneWidget);
      expect(find.text('中号文本按钮'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'AppResponsiveActionBar adapts gracefully on 320px without overflow',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16.0),
              child: AppResponsiveActionBar(
                children: [
                  AppActionButton.primary(
                    label: '确定保存当前叙事设定',
                    onPressed: () {},
                  ),
                  AppActionButton.secondary(
                    label: '导出世界观配置文件',
                    onPressed: () {},
                  ),
                  AppActionButton.danger(
                    label: '删除角色卡',
                    onPressed: () {},
                  ),
                  AppActionButton.text(
                    label: '稍后再说',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('确定保存当前叙事设定'), findsOneWidget);
      expect(find.text('导出世界观配置文件'), findsOneWidget);
      expect(find.text('删除角色卡'), findsOneWidget);
      expect(find.text('稍后再说'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppResponsiveActionBar forceColumnOnCompact works',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: AppResponsiveActionBar(
              forceColumnOnCompact: true,
              children: [
                AppActionButton.primary(
                  label: '继续探险',
                  fullWidth: true,
                  onPressed: () {},
                ),
                AppActionButton.secondary(
                  label: '返回大厅',
                  fullWidth: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('继续探险'), findsOneWidget);
      expect(find.text('返回大厅'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 1 - AppTextField Multiline & Keyboard Insets', () {
    testWidgets(
        'AppTextField handles multiline, helper, error, and scrollPadding',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestApp(
          viewInsets: const EdgeInsets.only(bottom: 260),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  AppTextField(
                    label: '超长中文世界观名称与叙事场景背景描述',
                    hintText: '输入世界观核心机制...',
                    helperText: '支持 Markdown 语法与自定义扩展实体属性定义说明',
                    maxLines: 4,
                  ),
                  SizedBox(height: 16),
                  AppTextField(
                    label: '异常参数校验字段',
                    errorText: '当前输入内容存在未知非法控制字符，请检查格式后重试',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('超长中文世界观名称与叙事场景背景描述'), findsOneWidget);
      expect(find.text('输入世界观核心机制...'), findsOneWidget);
      expect(find.text('支持 Markdown 语法与自定义扩展实体属性定义说明'), findsOneWidget);
      expect(find.text('当前输入内容存在未知非法控制字符，请检查格式后重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppTextField dark theme and high text scale (1.5x)',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestApp(
          themeMode: ThemeMode.dark,
          textScaleFactor: 1.5,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: AppTextField(
                  label: '角色卡称谓',
                  hintText: '请输入角色姓名',
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('角色卡称谓'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 1 - AppSelect & LtSelect & AppDropdown', () {
    testWidgets('AppSelect unexpanded with long text avoids overflow on 320px',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      String? selected = 'deepseek-chat-v3-extremely-long-identifier-name';

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Center(
              child: Row(
                children: [
                  const Text('模型:'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppSelect<String>(
                      value: selected,
                      expanded: false,
                      items: const [
                        AppSelectItem(
                          value:
                              'deepseek-chat-v3-extremely-long-identifier-name',
                          label:
                              'deepseek-chat-v3-extremely-long-identifier-name-with-extra-text',
                        ),
                      ],
                      onChanged: (val) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('AppSelect mobile sheet scrolls through 20 items on 320px',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      String? current = 'item_0';
      final items = List.generate(
        20,
        (i) => AppSelectItem(
          value: 'item_$i',
          label: '叙事角色选项 $i: 苍茫群山深处的古老守卫者 ($i)',
          subtitle: '等级: $i · 阵营: 密林守护联盟',
        ),
      );

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: AppSelect<String>(
                    label: '出场NPC选择',
                    value: current,
                    items: items,
                    onChanged: (val) => setState(() => current = val),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击打开 BottomSheet
      await tester.tap(find.byType(AppSelect<String>));
      await tester.pumpAndSettle();

      expect(find.text('出场NPC选择'), findsWidgets);
      expect(find.text('叙事角色选项 0: 苍茫群山深处的古老守卫者 (0)'), findsNWidgets(2));

      // 选择第 3 项
      await tester.tap(find.text('叙事角色选项 3: 苍茫群山深处的古老守卫者 (3)'));
      await tester.pumpAndSettle();

      expect(current, 'item_3');
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 1 - AppErrorView & Sanitization', () {
    test('sanitizeErrorText redacts API keys, SQL, paths, and traces', () {
      const rawError = '''
DatabaseException(SELECT * FROM adventures WHERE id = 1)
apiKey: sk-1234567890abcdef1234567890
Failed to open /home/yrz/LT/database/dev.sqlite
Authorization: Bearer my_super_secret_token_12345
standaloneToken: Bearer standalone_token_67890
#0 MyApp.run (/home/yrz/LT/lib/main.dart:42)
#1 dart:core
''';

      final sanitized = AppErrorView.sanitizeErrorText(rawError)!;

      // 验证敏感信息均被安全脱敏
      expect(sanitized.contains('sk-1234567890'), isFalse);
      expect(sanitized.contains('[REDACTED_KEY]'), isTrue);
      expect(sanitized.contains('my_super_secret_token_12345'), isFalse);
      expect(sanitized.contains('Authorization: [REDACTED]'), isTrue);
      expect(sanitized.contains('Bearer [REDACTED]'), isTrue);
      expect(sanitized.contains('SELECT * FROM'), isFalse);
      expect(sanitized.contains('[DATABASE_QUERY]'), isTrue);
      expect(sanitized.contains('/home/yrz/LT'), isFalse);
      expect(sanitized.contains('[INTERNAL_PATH]'), isTrue);
      expect(sanitized.contains('#0 MyApp'), isFalse);
    });

    testWidgets('AppErrorView renders on 320px with retry callback',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      bool retried = false;

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: AppErrorView(
              title: '网络同步异常',
              message: '无法连接到远程叙事服务器，请检查本地网络连接状态。',
              details:
                  'GET https://api.narrative.ai/v1/sync failed with timeout',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('网络同步异常'), findsOneWidget);
      expect(find.text('无法连接到远程叙事服务器，请检查本地网络连接状态。'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 1 - AppLoadingView & AppEmptyState / AppEmptyView', () {
    testWidgets('AppLoadingView renders on 320px and large text scale',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestApp(
          textScaleFactor: 1.5,
          home: const Scaffold(
            body: AppLoadingView(
              message: '正在加载冒险世界模型与场景实体数据，请稍候...',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('正在加载冒险世界模型与场景实体数据，请稍候...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppEmptyView renders on 320px with action button',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      bool actionTapped = false;

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: AppEmptyView(
              title: '尚未创建任何世界观',
              description: '点击下方按钮开始构思并创建你的第一个沉浸式叙事宇宙',
              actionLabel: '新建世界观',
              onAction: () => actionTapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('尚未创建任何世界观'), findsOneWidget);
      expect(find.text('点击下方按钮开始构思并创建你的第一个沉浸式叙事宇宙'), findsOneWidget);
      expect(find.text('新建世界观'), findsOneWidget);

      await tester.tap(find.text('新建世界观'));
      await tester.pump();
      expect(actionTapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 1 - FormSubPageScaffold & AppPageScaffold Responsive Tests', () {
    for (final size in requiredUiViewports) {
      testWidgets('FormSubPageScaffold renders on ${size.width}x${size.height}',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);

        await tester.pumpWidget(
          buildTestApp(
            home: FormSubPageScaffold(
              title: '创建新角色卡 - 艾尔登大陆的流浪法师',
              scrollable: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.help_outline),
                  onPressed: () {},
                ),
              ],
              bottomBar: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.grey.withValues(alpha: 0.1),
                child: AppResponsiveActionBar(
                  children: [
                    AppActionButton.primary(
                      label: '保存角色卡',
                      onPressed: () {},
                    ),
                    AppActionButton.secondary(
                      label: '取消',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppTextField(
                      label: '角色姓名',
                      hintText: '例如: 卡尔·影歌',
                    ),
                    SizedBox(height: 16),
                    AppTextField(
                      label: '角色背景故事',
                      hintText: '出生于边境古老森林深处的秘术学徒...',
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('创建新角色卡 - 艾尔登大陆的流浪法师'), findsOneWidget);
        expect(find.text('保存角色卡'), findsOneWidget);
        expect(find.text('角色姓名'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('AppPageScaffold handles large font scale 2.0x on 320px',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestApp(
          textScaleFactor: 2.0,
          home: const AppPageScaffold(
            title: '大字号模式测试标题',
            body: Center(
              child: Text('正文大字号测试'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('大字号模式测试标题'), findsOneWidget);
      expect(find.text('正文大字号测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
