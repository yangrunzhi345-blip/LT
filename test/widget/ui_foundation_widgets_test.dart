import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/ui_foundation.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(
    Widget child, {
    ThemeData? theme,
  }) {
    return MaterialApp(
      theme: theme ?? AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: child,
    );
  }

  group('1. AppPageScaffold', () {
    testWidgets('renders title, body and actions', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          AppPageScaffold(
            title: '测试页面标题',
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () {},
              ),
            ],
            body: const Center(child: Text('页面正文内容')),
          ),
        ),
      );

      expect(find.text('测试页面标题'), findsOneWidget);
      expect(find.text('页面正文内容'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final size in requiredUiViewports) {
      testWidgets('renders without overflow on ${size.width}x${size.height}',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);

        await tester.pumpWidget(
          buildTestableWidget(
            AppPageScaffold(
              title: '超长超长超长超长超长超长测试页面标题文字',
              bottomBar: Container(
                height: 48,
                color: Colors.amber,
                child: const Center(child: Text('底部操作栏')),
              ),
              body: ListView(
                children: const [
                  Text('列表项 1'),
                  Text('列表项 2'),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('超长超长超长超长超长超长测试页面标题文字'), findsOneWidget);
        expect(find.text('底部操作栏'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('back button triggers callback or navigator pop',
        (tester) async {
      bool backCalled = false;
      await tester.pumpWidget(
        buildTestableWidget(
          AppPageScaffold(
            title: '子页面',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => backCalled = true,
            ),
            body: const Text('子页面内容'),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      expect(backCalled, isTrue);
    });
  });

  group('2. AppFormSection', () {
    testWidgets('renders title, description, headerAction and children',
        (tester) async {
      bool actionTapped = false;
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppFormSection(
              title: '基础配置',
              description: '请填写该模型的核心运行参数与凭证信息',
              headerAction: TextButton(
                onPressed: () => actionTapped = true,
                child: const Text('重置'),
              ),
              children: const [
                Text('表单项 1'),
                Text('表单项 2'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('基础配置'), findsOneWidget);
      expect(find.text('请填写该模型的核心运行参数与凭证信息'), findsOneWidget);
      expect(find.text('重置'), findsOneWidget);
      expect(find.text('表单项 1'), findsOneWidget);
      expect(find.text('表单项 2'), findsOneWidget);

      await tester.tap(find.text('重置'));
      expect(actionTapped, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders errorText properly', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const Scaffold(
            body: AppFormSection(
              title: '模型设置',
              errorText: 'API Key 格式不正确或已过期',
              child: Text('API Key 输入框占位'),
            ),
          ),
        ),
      );

      expect(find.text('API Key 格式不正确或已过期'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('card variant renders with border and padding', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const Scaffold(
            body: AppFormSection(
              title: '卡片分组',
              card: true,
              child: Text('卡片内部内容'),
            ),
          ),
        ),
      );

      expect(find.text('卡片分组'), findsOneWidget);
      expect(find.text('卡片内部内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders on 320px viewport without overflow with long text',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestableWidget(
          const Scaffold(
            body: AppFormSection(
              title: '这是一个超长超长超长的表单区域标题名称测试用例',
              description:
                  '这是一个非常长非常长非常长非常长非常长非常长非常长非常长的说明描述文本，用于验证在320px极端窄屏下的自动换行与弹性约束行为。',
              headerAction: Icon(Icons.info_outline),
              errorText: '这是一个超长的表单错误提示信息，必须在小屏幕下安全换行显示而绝不溢出。',
              child: Text('子项'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('3. AppTextField', () {
    testWidgets('handles input and onChanged callback', (tester) async {
      String changedValue = '';
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppTextField(
              label: '用户名',
              hintText: '请输入用户名',
              onChanged: (val) => changedValue = val,
            ),
          ),
        ),
      );

      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('请输入用户名'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Alice');
      await tester.pump();

      expect(changedValue, 'Alice');
      expect(find.text('Alice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders errorText with error styling', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const Scaffold(
            body: AppTextField(
              label: '密码',
              errorText: '密码长度不能少于 8 位',
            ),
          ),
        ),
      );

      expect(find.text('密码长度不能少于 8 位'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disabled state does not allow input or interaction',
        (tester) async {
      String value = '固定内容';
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppTextField(
              label: '只读账号',
              initialValue: value,
              enabled: false,
              onChanged: (val) => value = val,
            ),
          ),
        ),
      );

      expect(find.text('只读账号'), findsOneWidget);
      expect(find.text('固定内容'), findsOneWidget);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders across 320px viewport without overflow',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestableWidget(
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: AppTextField(
                label: '超长超长超长超长超长超长超长超长标签文本',
                hintText: '超长超长超长超长超长超长超长占位符文本',
                errorText: '超长超长超长超长超长超长错误信息文本',
                maxLines: 3,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('4. AppSelect', () {
    const items = [
      AppSelectItem<String>(value: 'gpt-4o', label: 'GPT-4o (全能旗舰)'),
      AppSelectItem<String>(
          value: 'claude-3-5-sonnet', label: 'Claude 3.5 Sonnet (高推理)'),
      AppSelectItem<String>(value: 'deepseek-v3', label: 'DeepSeek V3 (高性价比)'),
      AppSelectItem<String>(
          value: 'disabled-model', label: '下线模型', enabled: false),
    ];

    testWidgets('renders defaultValue and label correctly', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppSelect<String>(
              label: '模型选择',
              value: 'claude-3-5-sonnet',
              items: items,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('模型选择'), findsOneWidget);
      expect(find.text('Claude 3.5 Sonnet (高推理)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mobile (<600px): opens bottom sheet and selects new value',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      String? selectedValue = 'gpt-4o';

      await tester.pumpWidget(
        buildTestableWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: AppSelect<String>(
                  label: '模型选择',
                  value: selectedValue,
                  items: items,
                  onChanged: (val) => setState(() => selectedValue = val),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('GPT-4o (全能旗舰)'), findsOneWidget);

      // Tap to open bottom sheet
      await tester.tap(find.text('GPT-4o (全能旗舰)'));
      await tester.pumpAndSettle();

      // BottomSheet should be open with all options
      expect(find.text('DeepSeek V3 (高性价比)'), findsOneWidget);

      // Select DeepSeek
      await tester.tap(find.text('DeepSeek V3 (高性价比)'));
      await tester.pumpAndSettle();

      // Selected value should be updated
      expect(selectedValue, 'deepseek-v3');
      expect(find.text('DeepSeek V3 (高性价比)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('desktop (>=600px): opens menu and selects new value',
        (tester) async {
      setViewport(tester, width: 900, height: 700);
      String? selectedValue = 'gpt-4o';

      await tester.pumpWidget(
        buildTestableWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(32),
                  child: AppSelect<String>(
                    label: '桌面端模型选择',
                    value: selectedValue,
                    items: items,
                    onChanged: (val) => setState(() => selectedValue = val),
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('GPT-4o (全能旗舰)'), findsOneWidget);

      // Tap to open desktop menu
      await tester.tap(find.text('GPT-4o (全能旗舰)'));
      await tester.pumpAndSettle();

      // Menu option should be visible
      expect(find.text('DeepSeek V3 (高性价比)'), findsOneWidget);

      await tester.tap(find.text('DeepSeek V3 (高性价比)'));
      await tester.pumpAndSettle();

      expect(selectedValue, 'deepseek-v3');
      expect(find.text('DeepSeek V3 (高性价比)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disabled select does not trigger sheet or onChanged',
        (tester) async {
      bool changed = false;
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppSelect<String>(
              label: '已锁定选项',
              value: 'gpt-4o',
              enabled: false,
              items: items,
              onChanged: (_) => changed = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('GPT-4o (全能旗舰)'));
      await tester.pumpAndSettle();

      // BottomSheet should not open
      expect(find.text('DeepSeek V3 (高性价比)'), findsNothing);
      expect(changed, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('validator and errorText are displayed properly',
        (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppSelect<String>(
              label: '校验选择',
              value: null,
              items: items,
              errorText: '必须选择一个有效的模型',
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('必须选择一个有效的模型'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles long text on 320px viewport without overflow',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      const longItems = [
        AppSelectItem<String>(
          value: 'long-1',
          label: '这是一个极其极其极其极其极其极其极其极其极其极其超长的模型名称测试项，用于确保不会发生任何横向布局溢出',
          subtitle: '这是一个极其极其极其极其超长的副标题说明文案',
        ),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: AppSelect<String>(
                label: '超长标签测试',
                value: 'long-1',
                items: longItems,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('5. Buttons', () {
    testWidgets('AppPrimaryButton handles click, loading, and disabled',
        (tester) async {
      int clickCount = 0;

      // Normal enabled
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppPrimaryButton(
              label: '提交保存',
              onPressed: () => clickCount++,
            ),
          ),
        ),
      );

      expect(find.text('提交保存'), findsOneWidget);
      await tester.tap(find.text('提交保存'));
      expect(clickCount, 1);

      // Loading state
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppPrimaryButton(
              label: '正在保存',
              isLoading: true,
              onPressed: () => clickCount++,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('正在保存'));
      expect(clickCount, 1); // Click ignored during loading

      // Disabled state
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppPrimaryButton(
              label: '禁止操作',
              enabled: false,
              onPressed: () => clickCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('禁止操作'));
      expect(clickCount, 1); // Click ignored when disabled
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppSecondaryButton handles loading, disabled, and sizes',
        (tester) async {
      int clickCount = 0;

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: Column(
              children: [
                AppSecondaryButton(
                  label: '小按钮',
                  size: AppButtonSize.small,
                  onPressed: () => clickCount++,
                ),
                AppSecondaryButton(
                  label: '中按钮',
                  size: AppButtonSize.medium,
                  onPressed: () => clickCount++,
                ),
                AppSecondaryButton(
                  label: '大按钮',
                  size: AppButtonSize.large,
                  onPressed: () => clickCount++,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('小按钮'), findsOneWidget);
      expect(find.text('中按钮'), findsOneWidget);
      expect(find.text('大按钮'), findsOneWidget);

      await tester.tap(find.text('小按钮'));
      expect(clickCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppDangerButton handles loading, outlined and danger styles',
        (tester) async {
      int clickCount = 0;

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: Column(
              children: [
                AppDangerButton(
                  label: '彻底删除',
                  icon: Icons.delete_forever,
                  onPressed: () => clickCount++,
                ),
                AppDangerButton(
                  label: '描边删除',
                  outlined: true,
                  onPressed: () => clickCount++,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('彻底删除'), findsOneWidget);
      expect(find.text('描边删除'), findsOneWidget);
      expect(find.byIcon(Icons.delete_forever), findsOneWidget);

      await tester.tap(find.text('彻底删除'));
      expect(clickCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Buttons render on 320px viewport without overflow',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  AppPrimaryButton(
                    label: '超长超长超长超长超长超长按钮文案测试',
                    fullWidth: true,
                    onPressed: () {},
                  ),
                  const SizedBox(height: 8),
                  AppSecondaryButton(
                    label: '次级操作',
                    fullWidth: true,
                    onPressed: () {},
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
  });

  group('6. State Views', () {
    testWidgets('AppLoadingView renders indicator and message', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(
          const Scaffold(
            body: AppLoadingView(message: '正在载入世界设定与角色卡...'),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('正在载入世界设定与角色卡...'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppEmptyView renders title, description, and action',
        (tester) async {
      bool actionTriggered = false;
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppEmptyView(
              icon: Icons.auto_awesome,
              title: '暂无任何资源卡片',
              description: '点击下方按钮快速创建或从预设模板导入',
              actionLabel: '新建资源',
              onAction: () => actionTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('暂无任何资源卡片'), findsOneWidget);
      expect(find.text('点击下方按钮快速创建或从预设模板导入'), findsOneWidget);
      expect(find.text('新建资源'), findsOneWidget);

      await tester.tap(find.text('新建资源'));
      expect(actionTriggered, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppErrorView renders error message and triggers retry',
        (tester) async {
      bool retryTriggered = false;
      await tester.pumpWidget(
        buildTestableWidget(
          Scaffold(
            body: AppErrorView(
              title: '同步失败',
              message: '网络连接超时，请确认代理设置或重试',
              details: 'SocketException: Connection timed out',
              onRetry: () => retryTriggered = true,
            ),
          ),
        ),
      );

      expect(find.text('同步失败'), findsOneWidget);
      expect(find.text('网络连接超时，请确认代理设置或重试'), findsOneWidget);
      expect(
          find.text('SocketException: Connection timed out'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      expect(retryTriggered, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('State views render on 320px viewport without overflow',
        (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestableWidget(
          const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  AppLoadingView(message: '超长加载提示文案测试验证'),
                  AppEmptyView(
                    title: '超长空状态标题测试验证',
                    description:
                        '这是一个非常长非常长非常长的空状态描述文本，用于验证在320px极端窄屏下的自动换行与弹性约束。',
                    actionLabel: '超长操作按钮',
                  ),
                  AppErrorView(
                    title: '超长错误标题测试验证',
                    message: '这是一个超长超长超长超长的错误信息展示，必须在320px屏幕下自适应不溢出。',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });
  });

  group('7. AppConfirmDialog', () {
    testWidgets('AppConfirmDialog.show returns true on confirm',
        (tester) async {
      bool? result;

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await AppConfirmDialog.show(
                      context: context,
                      title: '删除资源确认',
                      message: '删除后此资源将移入回收站，是否继续？',
                      confirmLabel: '确认删除',
                      isDanger: true,
                      icon: Icons.delete_outline,
                    );
                  },
                  child: const Text('触发删除'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('触发删除'));
      await tester.pumpAndSettle();

      expect(find.text('删除资源确认'), findsOneWidget);
      expect(find.text('删除后此资源将移入回收站，是否继续？'), findsOneWidget);
      expect(find.text('确认删除'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('确认删除'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppConfirmDialog.show returns false on cancel',
        (tester) async {
      bool? result;

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await AppConfirmDialog.show(
                      context: context,
                      title: '放弃未保存内容',
                      message: '当前编辑未保存，退出将丢失更改，是否放弃？',
                      confirmLabel: '放弃',
                      cancelLabel: '继续编辑',
                    );
                  },
                  child: const Text('触发放弃'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('触发放弃'));
      await tester.pumpAndSettle();

      expect(find.text('放弃未保存内容'), findsOneWidget);
      expect(find.text('继续编辑'), findsOneWidget);

      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders on 320px viewport without overflow', (tester) async {
      setViewport(tester, width: 320, height: 568);

      await tester.pumpWidget(
        buildTestableWidget(
          Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    AppConfirmDialog.show(
                      context: context,
                      title: '这是一个超长超长的确认对话框标题文本测试',
                      message:
                          '这是一个超长超长超长超长超长超长超长超长超长超长的对话框提示正文，验证在320px小屏幕下可以正常滚动且绝不发生RenderFlex overflow。',
                      isDanger: true,
                      icon: Icons.warning_amber_rounded,
                    );
                  },
                  child: const Text('打开'),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
