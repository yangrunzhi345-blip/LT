import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/theme/app_dimensions.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_svg_icon.dart';
import 'package:lt_dialogue/core/widgets/workbench_chrome.dart';
import 'package:lt_dialogue/features/adventure/presentation/templates/screens/preset_scenes_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
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

import '../helpers/responsive_test_helper.dart';

/// Serves an empty preset list without touching the real template query.
class _EmptyResourceCrudController extends ResourceCrudController {
  _EmptyResourceCrudController()
      : super(
          repository:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
        );

  @override
  Future<List<Map<String, dynamic>>> loadAdventureTemplates({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];
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

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    );

/// Workbench page chrome convergence: Resource Library and Preset Scenes must
/// present the same header surface, back action, control heights, toolbar and
/// search field. These tests pin the shared components and prove neither page
/// drifts back to a bespoke AppBar / filled return CTA.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(
                'dev.fluttercommunity.plus/connectivity_status'),
            (_) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => <String>['wifi']);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'deepseek_api_key': 'test',
      'openai_api_key': 'test',
    });
    tempDir = await Directory.systemTemp.createTemp('lt_page_chrome_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<void> pumpLibrary(WidgetTester tester, Size size) async {
    setViewport(tester, width: size.width, height: size.height);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          home: ResourceLibraryScreen(onMenuPressed: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> pumpPreset(WidgetTester tester, Size size) async {
    setViewport(tester, width: size.width, height: size.height);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatProvider.overrideWith((ref) => _TestChatProvider()),
          resourceCrudControllerProvider
              .overrideWith((ref) => _EmptyResourceCrudController()),
        ],
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
  }

  group('WorkbenchBackAction', () {
    testWidgets('desktop is a quiet 32 px TextButton with a back icon',
        (tester) async {
      setViewport(tester, width: 1280, height: 800);
      await tester.pumpWidget(_host(WorkbenchBackAction(
        onPressed: () {},
        label: 'Return to Lobby',
      )));
      await tester.pumpAndSettle();

      expect(find.byType(TextButton), findsOneWidget);
      // Navigation, never a CTA: no filled / tonal presentation.
      expect(find.byType(FilledButton), findsNothing);
      expect(
        tester.getSize(find.byType(TextButton)).height,
        AppDimensions.controlHeightSm,
      );
      expect(find.text('Return to Lobby'), findsOneWidget);

      final icon = tester.widget<AppSvgIcon>(find.descendant(
        of: find.byType(TextButton),
        matching: find.byType(AppSvgIcon),
      ));
      expect(icon.name, 'back');
      expect(icon.size, 16);
    });

    testWidgets('compact collapses to a tooltip icon button without text',
        (tester) async {
      setViewport(tester, width: 320, height: 800);
      await tester.pumpWidget(_host(WorkbenchBackAction(
        onPressed: () {},
        label: 'Return to Lobby',
      )));
      await tester.pumpAndSettle();

      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(IconButton), findsOneWidget);
      // Same label, surfaced as tooltip / accessible name only.
      expect(find.byTooltip('Return to Lobby'), findsOneWidget);
      expect(find.text('Return to Lobby'), findsNothing);

      final icon = tester.widget<AppSvgIcon>(find.descendant(
        of: find.byType(IconButton),
        matching: find.byType(AppSvgIcon),
      ));
      expect(icon.name, 'back');
    });

    testWidgets('compact action exposes an accessible name', (tester) async {
      setViewport(tester, width: 320, height: 800);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(WorkbenchBackAction(
        onPressed: () {},
        label: 'Return to Lobby',
      )));
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(find.byType(IconButton)),
        isSemantics(tooltip: 'Return to Lobby', isButton: true),
      );
      handle.dispose();
    });

    testWidgets('renders in both light and dark themes', (tester) async {
      setViewport(tester, width: 1280, height: 800);
      for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
        await tester.pumpWidget(_host(
          WorkbenchBackAction(onPressed: () {}, label: 'Return to Lobby'),
          theme: theme,
        ));
        await tester.pumpAndSettle();
        expect(find.byType(TextButton), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('WorkbenchSearchField', () {
    testWidgets('owns the 34 px / filled / bordered search contract',
        (tester) async {
      setViewport(tester, width: 400, height: 800);
      await tester.pumpWidget(_host(WorkbenchSearchField(
        hintText: 'Search',
        onChanged: (_) {},
      )));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(TextField)).height, 34);
      final field = tester.widget<TextField>(find.byType(TextField));
      final decoration = field.decoration!;
      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, isNotNull);
      expect(decoration.hintText, 'Search');
    });
  });

  group('Resource Library page chrome', () {
    testWidgets('return uses WorkbenchBackAction beside the menu control',
        (tester) async {
      await pumpLibrary(tester, const Size(1280, 900));

      expect(find.byType(WorkbenchPageHeader), findsOneWidget);
      expect(find.byType(WorkbenchBackAction), findsOneWidget);
      expect(find.byKey(const Key('resource-library-return-home')),
          findsOneWidget);
      expect(find.byKey(const Key('resource-library-menu')), findsOneWidget);
      // The return path is quiet text, not a filled CTA.
      expect(
        find.descendant(
          of: find.byKey(const Key('resource-library-return-home')),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
      // Primary "new" action is preserved.
      expect(find.byKey(const Key('resource-create-button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('has no overflow at 320 px with menu and back both present',
        (tester) async {
      await pumpLibrary(tester, const Size(320, 568));

      expect(find.byKey(const Key('resource-library-menu')), findsOneWidget);
      expect(find.byKey(const Key('resource-library-return-home')),
          findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Preset Scenes page chrome', () {
    testWidgets('uses WorkbenchPageHeader, not a legacy AppBar',
        (tester) async {
      await pumpPreset(tester, const Size(1280, 900));

      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(WorkbenchPageHeader), findsOneWidget);
      expect(find.byType(WorkbenchBackAction), findsOneWidget);
      expect(find.byKey(const Key('preset-return-home')), findsOneWidget);

      // Same back component as Resource Library, so the return action is
      // identical (a quiet TextButton, not a FilledButton.tonalIcon).
      expect(find.byType(TextButton), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const Key('preset-return-home')),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
      expect(find.text('返回大厅'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('title shares the workbench titleLarge typography',
        (tester) async {
      await pumpPreset(tester, const Size(1280, 900));

      final theme = Theme.of(tester.element(find.byType(WorkbenchPageHeader)));
      final title = tester.widget<Text>(find.text('预存场景工坊'));
      expect(title.style?.fontSize, theme.textTheme.titleLarge?.fontSize);
      expect(title.style?.fontWeight, isNot(FontWeight.w800));
    });

    testWidgets('create stays primary and refresh is available',
        (tester) async {
      await pumpPreset(tester, const Size(1280, 900));

      final create = find.byKey(const Key('preset-create-button'));
      expect(create, findsOneWidget);
      expect(tester.widget(create), isA<FilledButton>());

      final refresh = find.byKey(const Key('preset-refresh-button'));
      expect(refresh, findsOneWidget);
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('has no overflow at 320 px and keeps controls reachable',
        (tester) async {
      await pumpPreset(tester, const Size(320, 568));

      expect(find.byKey(const Key('preset-return-home')), findsOneWidget);
      expect(find.byKey(const Key('preset-create-button')), findsOneWidget);
      expect(find.byKey(const Key('preset-refresh-button')), findsOneWidget);
      // Compact header drops the return label in favour of an icon.
      expect(find.text('返回大厅'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
