import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_dropdown.dart';

void main() {
  group('AppDropdown Widget Tests', () {
    testWidgets('AppDropdown.compact renders and selects option', (tester) async {
      String? selected = 'option1';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: AppDropdown<String>.compact(
                    value: selected,
                    options: const [
                      AppDropdownOption(value: 'option1', label: '选项一 (主角)'),
                      AppDropdownOption(value: 'option2', label: '选项二 (同伴)'),
                      AppDropdownOption(value: 'option3', label: '选项三 (导师)'),
                    ],
                    onChanged: (val) {
                      setState(() => selected = val);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('选项一 (主角)'), findsOneWidget);

      // 点击打开下拉浮层
      await tester.tap(find.text('选项一 (主角)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 验证浮层中的选项
      expect(find.text('选项二 (同伴)'), findsOneWidget);
      expect(find.text('选项三 (导师)'), findsOneWidget);

      // 选择选项二
      await tester.tap(find.text('选项二 (同伴)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(selected, 'option2');
      expect(find.text('选项二 (同伴)'), findsOneWidget);
    });

    testWidgets('AppDropdown.form renders with label and handles selection', (tester) async {
      String? model = 'deepseek-v4-pro';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: AppDropdown<String>.form(
                    label: '首选大语言模型',
                    value: model,
                    options: const [
                      AppDropdownOption(
                        value: 'deepseek-v4-pro',
                        label: 'deepseek-v4-pro',
                        icon: Icons.psychology_outlined,
                        subtitle: '深度推演',
                      ),
                      AppDropdownOption(
                        value: 'deepseek-v4-flash',
                        label: 'deepseek-v4-flash',
                        icon: Icons.bolt_rounded,
                        subtitle: '极速叙事',
                      ),
                    ],
                    onChanged: (val) {
                      setState(() => model = val);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('首选大语言模型'), findsOneWidget);
      expect(find.text('deepseek-v4-pro'), findsOneWidget);

      // 打开浮层
      await tester.tap(find.text('deepseek-v4-pro'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('极速叙事'), findsOneWidget);

      await tester.tap(find.text('deepseek-v4-flash'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(model, 'deepseek-v4-flash');
    });

    testWidgets('AppMultiSelectDropdown toggles multiple values', (tester) async {
      Set<String> selected = {'tag1'};

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: AppMultiSelectDropdown<String>(
                    label: '特征标签',
                    values: selected,
                    options: const [
                      AppDropdownOption(value: 'tag1', label: '剑术'),
                      AppDropdownOption(value: 'tag2', label: '奥术魔法'),
                      AppDropdownOption(value: 'tag3', label: '机械工程'),
                    ],
                    onChanged: (vals) {
                      setState(() => selected = vals);
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('已选 1 项'), findsOneWidget);

      // 打开浮层
      await tester.tap(find.text('已选 1 项'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('奥术魔法'), findsOneWidget);

      // 勾选第二项
      await tester.tap(find.text('奥术魔法'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(selected.contains('tag2'), isTrue);
      expect(selected.length, 2);

      // 点击外部关闭浮层
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('AppDropdown defaults to popping downward', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.center,
              child: AppDropdown<String>.compact(
                value: 'item1',
                options: const [
                  AppDropdownOption(value: 'item1', label: '条目 1'),
                  AppDropdownOption(value: 'item2', label: '条目 2'),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final triggerFinder = find.text('条目 1');
      final triggerRect = tester.getRect(triggerFinder);

      // 打开浮层
      await tester.tap(triggerFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final option2Finder = find.text('条目 2');
      expect(option2Finder, findsOneWidget);
      final option2Rect = tester.getRect(option2Finder);

      // 验证弹出的选项在触发器下方 (Downward)
      expect(option2Rect.top, greaterThan(triggerRect.bottom));

      // 关闭浮层
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('AppDropdown inside SingleChildScrollView does not throw unbounded height error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  AppDropdown<String>.form(
                    label: '测试字段',
                    value: '1',
                    expanded: true,
                    options: const [
                      AppDropdownOption(value: '1', label: '值 1'),
                      AppDropdownOption(value: '2', label: '值 2'),
                    ],
                    onChanged: (_) {},
                  ),
                  AppMultiSelectDropdown<String>(
                    label: '多选测试',
                    values: const {'a'},
                    expanded: true,
                    options: const [
                      AppDropdownOption(value: 'a', label: '选项 A'),
                    ],
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('测试字段'), findsOneWidget);
      expect(find.text('多选测试'), findsOneWidget);
    });
  });
}
