import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_action_menu.dart';
import 'package:lt_dialogue/core/widgets/app_dropdown.dart';
import 'package:lt_dialogue/core/widgets/app_select.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';

/// Component contract for the single shared menu kernel. Every dropdown /
/// action / multi-select surface must render through it, so these assertions
/// describe the shared visual and behavioural rules rather than one widget.
void main() {
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(900, 700),
    bool dark = false,
    Locale locale = const Locale('zh'),
  }) async {
    setViewport(tester, width: size.width, height: size.height);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
  }

  Widget select({bool enabled = true, ValueChanged<String?>? onChanged}) =>
      StatefulBuilder(
        builder: (context, setState) => AppSelect<String>(
          label: '模型',
          value: 'a',
          enabled: enabled,
          items: const [
            AppSelectItem(value: 'a', label: '模型 A'),
            AppSelectItem(value: 'b', label: '模型 B', subtitle: '备用模型'),
            AppSelectItem(value: 'c', label: '模型 C', enabled: false),
          ],
          onChanged: (value) {
            onChanged?.call(value);
            setState(() {});
          },
        ),
      );

  group('desktop select', () {
    testWidgets('opens the shared menu with selected state and a check',
        (tester) async {
      String? picked;
      await mount(tester, select(onChanged: (value) => picked = value));
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();

      expect(find.byType(MenuAnchor), findsOneWidget);
      expect(find.text('模型 B'), findsOneWidget);
      expect(find.text('模型 C'), findsOneWidget);

      // The current value is marked with the shared selected treatment: a
      // quiet primary tint, a w600 label and a primary check.
      final selectedButton = tester.widget<MenuItemButton>(
        find.ancestor(
          of: find.text('模型 A').last,
          matching: find.byType(MenuItemButton),
        ),
      );
      final scheme =
          Theme.of(tester.element(find.byType(MenuAnchor))).colorScheme;
      expect(
        selectedButton.style?.backgroundColor?.resolve(<WidgetState>{}),
        scheme.primary.withValues(alpha: 0.08),
      );
      expect(find.byType(MenuItemButton), findsNWidgets(3));
      // The selected entry carries the shared primary check glyph.
      expect(
        find.byWidgetPredicate(
            (widget) => widget is AppSvgIcon && widget.name == 'check'),
        findsOneWidget,
      );

      await tester.tap(find.text('模型 B'));
      await tester.pumpAndSettle();
      expect(picked, 'b');
      expect(tester.takeException(), isNull);
    });

    testWidgets('disabled entries cannot be activated', (tester) async {
      String? picked;
      await mount(tester, select(onChanged: (value) => picked = value));
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();

      final disabled = tester.widget<MenuItemButton>(
        find.ancestor(
          of: find.text('模型 C').last,
          matching: find.byType(MenuItemButton),
        ),
      );
      expect(disabled.onPressed, isNull);
      await tester.tap(find.text('模型 C'));
      await tester.pumpAndSettle();
      expect(picked, isNull, reason: 'a disabled entry must not activate');
      expect(tester.takeException(), isNull);
    });

    testWidgets('subtitle renders and long labels never overflow',
        (tester) async {
      await mount(
        tester,
        AppSelect<String>(
          label: '模型',
          value: 'a',
          items: const [
            AppSelectItem(value: 'a', label: '模型 A'),
            AppSelectItem(
              value: 'b',
              label: '一个用于验证超长标签在菜单中被正确截断而不会触发溢出的模型名称',
              subtitle: '一段同样很长但允许换行到两行的副标题说明文字用于验证布局约束策略是否正确',
            ),
          ],
          onChanged: (_) {},
        ),
      );
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();
      expect(find.text('一段同样很长但允许换行到两行的副标题说明文字用于验证布局约束策略是否正确'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('desktop action menu', () {
    testWidgets('destructive, divider and disabled semantics', (tester) async {
      String? action;
      await mount(
        tester,
        AppActionMenu<String>(
          items: const [
            AppActionMenuItem(value: 'edit', label: '编辑', icon: 'edit'),
            AppActionMenuItem(value: 'move', label: '移动', enabled: false),
            AppActionMenuItem(
              value: 'delete',
              label: '删除',
              icon: 'delete',
              destructive: true,
              dividerBefore: true,
            ),
          ],
          onSelected: (value) => action = value,
        ),
      );
      await tester.tap(find.byType(AppActionMenu<String>));
      await tester.pumpAndSettle();

      final scheme =
          Theme.of(tester.element(find.byType(MenuAnchor))).colorScheme;
      final deleteText = tester.widget<Text>(find.text('删除'));
      expect(deleteText.style?.color, scheme.error);
      // Divider groups the destructive entry away from the safe actions.
      expect(
          find.descendant(
            of: find.byType(MenuAnchor),
            matching: find.byType(Divider),
          ),
          findsWidgets);

      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(action, 'edit');
      expect(tester.takeException(), isNull);
    });
  });

  group('multi select', () {
    testWidgets('toggles without closing and shows every check',
        (tester) async {
      Set<String> values = {'a'};
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => AppMultiSelectDropdown<String>(
            label: '标签',
            values: values,
            options: const [
              AppDropdownOption(value: 'a', label: '甲'),
              AppDropdownOption(value: 'b', label: '乙'),
            ],
            onChanged: (next) => setState(() => values = next),
          ),
        ),
      );
      await tester.tap(find.text('已选 1 项'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('乙'));
      await tester.pump();
      expect(values, {'a', 'b'});
      // Still open, so both checks are visible.
      expect(find.text('乙'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('menu surface contract', () {
    testWidgets('uses compact radius, one border and a bounded width/height',
        (tester) async {
      await mount(tester, select());
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();

      final anchor = tester.widget<MenuAnchor>(find.byType(MenuAnchor));
      final style = anchor.style!;
      final shape =
          style.shape?.resolve(<WidgetState>{}) as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(6));
      expect(shape.side.width, 1);
      expect(style.padding?.resolve(<WidgetState>{}), const EdgeInsets.all(4));
      expect(style.maximumSize?.resolve(<WidgetState>{})?.height, 380);
      expect(style.maximumSize!.resolve(<WidgetState>{})!.width,
          lessThanOrEqualTo(900 - 32));
      expect(anchor.animated, isFalse);
    });

    testWidgets('hover and selected overlays are the shared quiet tokens',
        (tester) async {
      await mount(tester, select());
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();
      final scheme =
          Theme.of(tester.element(find.byType(MenuAnchor))).colorScheme;
      final button = tester.widget<MenuItemButton>(
        find.ancestor(
          of: find.text('模型 B').last,
          matching: find.byType(MenuItemButton),
        ),
      );
      expect(
        button.style?.overlayColor?.resolve(<WidgetState>{WidgetState.hovered}),
        scheme.onSurface.withValues(alpha: 0.05),
      );
    });
  });

  group('toolbar presentation', () {
    testWidgets('renders a quiet label:value control, not a filled pill',
        (tester) async {
      var changed = false;
      await mount(
        tester,
        AppSelect<String>.toolbar(
          value: 'all',
          label: '状态',
          items: const [
            AppSelectItem(value: 'all', label: '全部状态'),
            AppSelectItem(value: 'ready', label: '已就绪'),
          ],
          onChanged: (_) => changed = true,
        ),
      );
      expect(find.textContaining('状态'), findsWidgets);
      expect(find.text('全部状态'), findsOneWidget);

      await tester.tap(find.byType(AppSelect<String>));
      await tester.pumpAndSettle();
      expect(find.text('已就绪'), findsOneWidget);
      await tester.tap(find.text('已就绪'));
      await tester.pumpAndSettle();
      expect(changed, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  group('responsive placement', () {
    testWidgets('compact 320 opens the shared BottomSheet without overflow',
        (tester) async {
      await mount(tester, select(), size: const Size(320, 568));
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('模型 B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('599 uses a BottomSheet', (tester) async {
      await mount(tester, select(), size: const Size(599, 700));
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('600 uses the anchored menu', (tester) async {
      await mount(tester, select(), size: const Size(600, 700));
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(MenuAnchor), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dismisses when tapping outside', (tester) async {
      await mount(tester, select());
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();
      expect(find.byType(MenuAnchor), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('模型 B'), findsNothing);
    });
  });

  group('theme and localization', () {
    testWidgets('renders in dark theme', (tester) async {
      await mount(tester, select(), dark: true);
      await tester.tap(find.text('模型 A'));
      await tester.pumpAndSettle();
      expect(find.text('模型 B'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bottom sheet title follows the active locale', (tester) async {
      await mount(
        tester,
        AppActionMenu<String>(
          items: const [AppActionMenuItem(value: 'x', label: 'Action X')],
          onSelected: (_) {},
        ),
        size: const Size(320, 568),
        locale: const Locale('en'),
      );
      await tester.tap(find.byType(AppActionMenu<String>));
      await tester.pumpAndSettle();
      expect(find.text('Actions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('null-valued select item', () {
    testWidgets('a null option is distinguishable from dismissal',
        (tester) async {
      var changed = false;
      String? value = 'assigned';
      await mount(
        tester,
        StatefulBuilder(
          builder: (context, setState) => AppSelect<String>(
            value: value,
            items: const [
              AppSelectItem(value: null, label: '不指定'),
              AppSelectItem(value: 'assigned', label: '已指定'),
            ],
            onChanged: (next) => setState(() {
              changed = true;
              value = next;
            }),
          ),
        ),
      );
      await tester.tap(find.text('已指定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不指定'));
      await tester.pumpAndSettle();
      expect(changed, isTrue);
      expect(value, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
