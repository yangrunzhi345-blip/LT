import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/controllers/adventure_template_controller.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_action_menu.dart';
import 'package:lt_dialogue/features/adventure/presentation/templates/screens/preset_scene_detail_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/templates/screens/preset_scenes_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';

/// Records mutations and serves a fixed template list so the card menu can be
/// driven without touching the real delete path.
class _RecordingResourceCrudController extends ResourceCrudController {
  _RecordingResourceCrudController(this.templates)
      : super(
          repository:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
        );

  final List<Map<String, dynamic>> templates;
  final List<String> deletedIds = <String>[];

  @override
  Future<List<Map<String, dynamic>>> loadAdventureTemplates({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      templates;

  @override
  Future<ResourceOperationResult> deleteAdventureTemplate(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    deletedIds.add(id);
    return const ResourceOperationResult.success(message: '已删除');
  }
}

class _TestChatProvider extends ChatProvider {
  _TestChatProvider()
      : super.withRepos(
          adventureRepo:
              AdventureRepositoryImpl(getDb: () => DatabaseService.database),
          worldEntryRepo:
              WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
          libraryRepo:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
          settingsRepo:
              SettingsRepositoryImpl(getDb: () => DatabaseService.database),
        );

  @override
  bool get isKeyConfigured => true;

  @override
  bool get isAdventureChatOpen => false;

  @override
  Future<int> startAdventureWithConfig(AdventureConfig c) async {
    setCurrentSection(AppSection.adventure);
    notifyListeners();
    return 1;
  }
}

Map<String, dynamic> _template({
  String id = 'template-menu-1',
  String name = '星际穿越探险',
}) {
  return {
    'id': id,
    'name': name,
    'worldview_name': '未来科幻',
    'worldview_desc': '浩瀚的银河时代',
    'status': 'complete',
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
    'char_data_json': jsonEncode({
      AdventureTemplateController.previewMarkerKey: true,
      'name': '舰长阿尔法',
      'worldview': '浩瀚的银河时代',
      'gender': '男',
      'age': '28',
      'protagonistClass': '指挥官',
      'protagonistBackground': '星际巡航舰队资深领航员',
      'openingScene': '警报声骤响，跃迁引擎发生轻微偏航。',
      'openingOptions': ['检查偏航数据', '联络领航副手'],
      'supportingCharacters': <dynamic>[],
    }),
  };
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;
    for (final name in const [
      'dev.fluttercommunity.plus/connectivity',
      'dev.fluttercommunity.plus/connectivity_status',
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(name), (call) async => null);
    }
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'deepseek_api_key': 'test', 'openai_api_key': 'test'});
    tempDir = await Directory.systemTemp.createTemp('lt_preset_menu_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<_RecordingResourceCrudController> pumpPresetScenesScreen(
    WidgetTester tester, {
    required Size viewport,
    List<Map<String, dynamic>>? templates,
  }) async {
    setViewport(tester, width: viewport.width, height: viewport.height);
    final crud = _RecordingResourceCrudController(templates ?? [_template()]);
    final overrides = <Object>[
      chatProvider.overrideWith((ref) => _TestChatProvider()),
      resourceCrudControllerProvider.overrideWith((ref) => crud),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides.cast(),
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: const PresetScenesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return crud;
  }

  Future<void> openMenu(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey<String>('preset-scene-menu-$id')));
    await tester.pumpAndSettle();
  }

  group('Preset scene card uses the unified AppActionMenu', () {
    testWidgets('desktop three-dot button opens the unified action menu',
        (tester) async {
      await pumpPresetScenesScreen(
        tester,
        viewport: const Size(1280, 800),
      );

      expect(find.byType(AppActionMenu<String>), findsOneWidget);
      await openMenu(tester, 'template-menu-1');

      expect(find.text('完整设定预览'), findsOneWidget);
      expect(find.text('载入向导微调'), findsOneWidget);
      expect(find.text('删除预存场景'), findsOneWidget);
      // The feature no longer builds its own popup menu.
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('delete entry is rendered with the destructive error color',
        (tester) async {
      await pumpPresetScenesScreen(
        tester,
        viewport: const Size(1280, 800),
      );
      final errorColor = Theme.of(
        tester.element(find.byType(PresetScenesScreen)),
      ).colorScheme.error;

      await openMenu(tester, 'template-menu-1');

      final deleteText = tester.widget<Text>(find.text('删除预存场景'));
      expect(deleteText.style?.color, errorColor);
      final previewText = tester.widget<Text>(find.text('完整设定预览'));
      expect(previewText.style?.color, isNot(errorColor));
    });

    testWidgets('完整设定预览 opens the preset detail page', (tester) async {
      await pumpPresetScenesScreen(
        tester,
        viewport: const Size(1280, 800),
      );
      await openMenu(tester, 'template-menu-1');

      await tester.tap(find.text('完整设定预览'));
      await tester.pumpAndSettle();

      expect(find.byType(PresetSceneDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('载入向导微调 opens the adventure wizard', (tester) async {
      await pumpPresetScenesScreen(
        tester,
        viewport: const Size(1280, 800),
      );
      await openMenu(tester, 'template-menu-1');

      await tester.tap(find.text('载入向导微调'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AdventureWizardScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('删除预存场景 goes through the shared confirmation and delete',
        (tester) async {
      final crud = await pumpPresetScenesScreen(
        tester,
        viewport: const Size(1280, 800),
      );
      await openMenu(tester, 'template-menu-1');

      await tester.tap(find.text('删除预存场景'));
      await tester.pumpAndSettle();

      // Shared confirmation dialog, not a bespoke menu-embedded action.
      expect(find.text('删除预存场景'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(crud.deletedIds, ['template-menu-1']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact 320px opens a touch-friendly bottom sheet menu',
        (tester) async {
      await pumpPresetScenesScreen(
        tester,
        viewport: const Size(320, 568),
      );
      await openMenu(tester, 'template-menu-1');

      expect(find.text('完整设定预览'), findsOneWidget);
      expect(find.text('载入向导微调'), findsOneWidget);
      expect(find.text('删除预存场景'), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('删除预存场景'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('menu remains usable on the required phone viewports',
        (tester) async {
      for (final viewport in requiredUiViewports) {
        await pumpPresetScenesScreen(tester, viewport: viewport);
        await openMenu(tester, 'template-menu-1');
        expect(
          find.text('删除预存场景'),
          findsOneWidget,
          reason: 'menu must open at ${viewport.width}x${viewport.height}',
        );
        expect(tester.takeException(), isNull);
        // Dismiss before the next viewport.
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
      }
    });
  });

  group('feature source no longer builds a PopupMenuButton', () {
    test('preset_scenes_screen.dart does not construct PopupMenu', () {
      final source = File(
        'lib/features/adventure/presentation/templates/screens/preset_scenes_screen.dart',
      ).readAsStringSync();
      expect(source.contains('PopupMenuButton'), isFalse);
      expect(source.contains('showMenu'), isFalse);
      expect(source.contains('OverlayEntry'), isFalse);
      expect(source.contains('AppActionMenu'), isTrue);
    });
  });
}
