import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/widgets/main_sidebar.dart';
import 'package:lt_dialogue/widgets/recent_adventure_list.dart';
import '../helpers/responsive_test_helper.dart';

class _SidebarChat extends ChangeNotifier implements ChatProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  bool expanded = true;
  AppSection section = AppSection.home;
  @override
  bool get isMainSidebarExpanded => expanded;
  bool configured = true;
  @override
  bool get isKeyConfigured => configured;
  @override
  bool get isAdventureChatOpen => opened != null;
  @override
  AppSection get currentSection => section;
  @override
  Future<void> loadMainSidebarPreference() async {}
  @override
  void toggleMainSidebarExpanded() {
    expanded = !expanded;
    notifyListeners();
  }

  @override
  void setCurrentSection(AppSection value) {
    section = value;
    notifyListeners();
  }

  final List<Map<String, dynamic>> records = [];
  int? opened;
  int? trashed;
  String? renamed;
  @override
  List<Map<String, dynamic>> get adventureList => records;
  @override
  int? get currentAdventureId => opened;
  @override
  Future<void> openAdventure(int id) async {
    opened = id;
    notifyListeners();
  }

  @override
  Future<void> renameAdventure(int id, String title) async {
    records.firstWhere((row) => row['id'] == id)['title'] = title;
    renamed = title;
    notifyListeners();
  }

  @override
  Future<void> moveAdventureToTrash(int id) async {
    trashed = id;
    records.removeWhere((row) => row['id'] == id);
    notifyListeners();
  }
}

void main() {
  group('Recent adventure sidebar', () {
    late _SidebarChat chat;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      chat = _SidebarChat();
    });
    Future<void> pump(WidgetTester tester,
        {double width = 1280,
        double height = 800,
        bool permanent = true,
        double scale = 1}) async {
      setViewport(tester, width: width, height: height);
      final scaffold = GlobalKey<ScaffoldState>();
      await tester.pumpWidget(ProviderScope(
          overrides: [chatProvider.overrideWith((ref) => chat)],
          child: MaterialApp(
              theme: AppTheme.light(),
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: Scaffold(
                  key: scaffold,
                  body: Align(
                      alignment: Alignment.centerLeft,
                      child: MainSidebar(
                          scaffoldKey: scaffold, permanent: permanent))))));
      await tester.pump();
    }

    void fill([int count = 150]) {
      final now = DateTime.now();
      chat.records.addAll(List.generate(
          count,
          (i) => {
                'id': i + 1,
                'title': i == 0 ? '这是一个非常长的冒险标题' * 20 : '冒险 ${i + 1}',
                'recent_activity_at':
                    now.subtract(Duration(days: i)).toIso8601String()
              }));
    }

    testWidgets(
        'empty list and full/medium fixed navigation with many histories',
        (tester) async {
      await pump(tester);
      expect(find.text('暂无历史冒险，点击启动向导开启新的征途'), findsOneWidget);
      fill();
      chat.notifyListeners();
      await tester.pump();
      final top =
          tester.getTopLeft(find.byKey(const Key('sidebar-nav-runtime')));
      final bottom =
          tester.getTopLeft(find.byKey(const Key('sidebar-nav-settings')));
      await tester.drag(find.byKey(const Key('sidebar-recent-scroll')),
          const Offset(0, -1600));
      await tester.pumpAndSettle();
      expect(
          tester.getTopLeft(find.byKey(const Key('sidebar-nav-runtime'))), top);
      expect(tester.getTopLeft(find.byKey(const Key('sidebar-nav-settings'))),
          bottom);
      await pump(tester, width: 768);
      expect(find.byType(RecentAdventureList), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('title ellipsis, click restore and selected in contextual page',
        (tester) async {
      fill(4);
      await pump(tester);
      final title =
          tester.widget<Text>(find.text(chat.records.first['title'] as String));
      expect(tester.getSize(find.byKey(const Key('recent-adventure-1'))).height,
          34);
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      await tester.tap(find.byKey(const Key('recent-adventure-1')));
      await tester.pump();
      expect(chat.opened, 1);
      chat.setCurrentSection(AppSection.runtimeState);
      await tester.pump();
      expect(
          tester
              .widget<Semantics>(find
                  .descendant(
                      of: find.byKey(const Key('recent-adventure-1')),
                      matching: find.byType(Semantics))
                  .at(1))
              .properties
              .selected,
          true);
    });

    testWidgets('hover menu renames and moves through trash action',
        (tester) async {
      fill(2);
      await pump(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
          tester.getCenter(find.byKey(const Key('recent-adventure-1'))));
      await tester.pump();
      await tester.tap(find.byTooltip('冒险操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '新的标题');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(chat.renamed, '新的标题');
      await tester.tap(find.byTooltip('冒险操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('移入回收站'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移入回收站').last);
      await tester.pumpAndSettle();
      expect(chat.trashed, 1);
      expect(find.text('新的标题'), findsNothing);
      await mouse.removePointer();
    });

    testWidgets(
        'keyboard focus reveals actions and temporal groups use activity',
        (tester) async {
      final now = DateTime.now();
      chat.records.addAll([
        for (final days in [0, 1, 3, 10])
          {
            'id': days + 1,
            'title': 'Story $days',
            'recent_activity_at':
                now.subtract(Duration(days: days)).toIso8601String()
          }
      ]);
      await tester.pumpWidget(MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: SizedBox(
                  width: 232,
                  child: RecentAdventureList(
                      adventures: chat.records,
                      selectedId: null,
                      onOpen: (_) {},
                      onRename: (_, __) {},
                      onTrash: (_, __) {})))));
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('昨天'), findsOneWidget);
      expect(find.text('过去 7 天'), findsOneWidget);
      expect(find.text('更早'), findsOneWidget);
      expect(tester.widget<Visibility>(find.byType(Visibility).first).visible,
          false);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.widget<Visibility>(find.byType(Visibility).first).visible,
          true);
      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.thumbVisibility, false);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(const Offset(200, 250));
      await tester.pump();
      expect(tester.widget<Scrollbar>(find.byType(Scrollbar)).thumbVisibility,
          true);
      await mouse.removePointer();
    });

    for (final viewport in requiredUiViewports) {
      testWidgets('History sheet fits ${viewport.width} and enlarged text',
          (tester) async {
        fill(30);
        chat.opened = 1;
        chat.configured = false;
        await pump(tester,
            width: viewport.width,
            height: viewport.height,
            permanent: viewport.width >= 600,
            scale: 2);
        expect(tester.takeException(), isNull);
        if (viewport.width < 600) {
          expect(find.byType(RecentAdventureList), findsNothing);
          await tester.tap(find.byKey(const Key('sidebar-nav-recent')));
          await tester.pumpAndSettle();
          expect(find.byType(RecentAdventureList), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      });
    }
    testWidgets('collapsed rail has history entry', (tester) async {
      fill(3);
      chat.toggleMainSidebarExpanded();
      await pump(tester);
      expect(find.byType(RecentAdventureList), findsNothing);
      await tester.tap(find.byKey(const Key('sidebar-nav-recent')));
      await tester.pumpAndSettle();
      expect(find.byType(RecentAdventureList), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
