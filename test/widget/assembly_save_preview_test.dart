import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/adventure/adventure_template_use_case.dart';
import 'package:lt_dialogue/controllers/adventure_template_controller.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_create_page.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_preview_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';

import '../helpers/responsive_test_helper.dart';

/// How the fake preview save resolves on this run.
enum _SaveOutcome { saved, duplicate, error }

class _RecordingTemplateController extends AdventureTemplateController {
  _RecordingTemplateController(this._outcome)
      : super(
          useCase: AdventureTemplateUseCase(
            LibraryRepositoryImpl(getDb: () => DatabaseService.database),
          ),
        );

  final _SaveOutcome _outcome;
  final List<
      ({
        String id,
        String name,
        String worldviewName,
        String worldviewDesc,
        AdventureConfig config,
      })> calls = [];

  @override
  Future<bool> saveAdventurePreview({
    required String id,
    required String name,
    required String worldviewName,
    required String worldviewDesc,
    required AdventureConfig config,
    String status = 'draft',
  }) async {
    if (_outcome == _SaveOutcome.error) {
      throw StateError('preview-save-boom');
    }
    calls.add((
      id: id,
      name: name,
      worldviewName: worldviewName,
      worldviewDesc: worldviewDesc,
      config: config,
    ));
    return _outcome == _SaveOutcome.saved;
  }
}

AdventureConfig _config() => AdventureConfig(
      worldview: '遗忘群岛',
      name: '亚瑟',
      gender: '男',
      age: '24',
      protagonistClass: '圣骑士',
      personality: '沉稳坚毅',
      protagonistBackground: '誓约王国的年轻骑士长',
      openingScene: '海风呼啸，战舰在暗礁前触底震颤。',
      openingOptions: const ['拔剑固守船头'],
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'char_arthur',
          characterId: 'char_arthur',
          characterName: '亚瑟',
          characterAvatar: '',
          isProtagonist: true,
          narrativeRole: AdventureCharacterRole.protagonist,
          customRoleName: '',
          sortOrder: 0,
          createdAt: '',
          updatedAt: '',
          characterCardJson: const {
            'name': '亚瑟',
            'gender': '男',
            'age': '24',
            'profession': '圣骑士',
          },
        ),
      ],
    );

void main() {
  final l10n = AppLocalizationsZh();
  late Directory tempDir;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_assembly_preview_');
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

  Widget host(
    Widget child,
    _RecordingTemplateController controller, {
    double textScale = 1.0,
    ThemeMode themeMode = ThemeMode.light,
  }) =>
      ProviderScope(
        overrides: [
          adventureTemplateControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          builder: textScale == 1.0
              ? null
              : (context, inner) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(textScale)),
                    child: inner!,
                  ),
          home: child,
        ),
      );

  Future<void> openPhase4(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('assembly-next-phase-button')));
      await tester.pumpAndSettle();
    }
  }

  group('AssemblyCreatePage save preview', () {
    testWidgets('saves the current assembly without launching', (tester) async {
      final controller = _RecordingTemplateController(_SaveOutcome.saved);
      var started = false;
      await tester.pumpWidget(host(
        AssemblyCreatePage(
          initialConfig: _config(),
          onStartAdventure: (_) async => started = true,
        ),
        controller,
      ));
      await tester.pumpAndSettle();
      await openPhase4(tester);

      expect(find.byKey(const Key('assembly-save-preview-button')),
          findsOneWidget);
      expect(find.text(l10n.savePreviewAction), findsOneWidget);
      // The preview save is secondary; the launch stays the only primary.
      expect(
        find.descendant(
          of: find.byKey(const Key('assembly-save-preview-button')),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('assembly-save-preview-button')));
      await tester.pumpAndSettle();

      expect(controller.calls, hasLength(1));
      final call = controller.calls.single;
      expect(call.id, startsWith('assembly_preview_'));
      expect(call.worldviewName, '遗忘群岛');
      expect(call.name, l10n.adventurePreviewName('遗忘群岛'));
      expect(call.config.openingOptions, contains('拔剑固守船头'));
      // Never launches, never leaves the page.
      expect(started, isFalse);
      expect(find.byType(AssemblyCreatePage), findsOneWidget);
      // Central feedback.
      expect(find.byKey(const Key('app-feedback-surface')), findsOneWidget);
      expect(
        find.text(l10n
            .adventurePreviewSavedMessage(l10n.adventurePreviewName('遗忘群岛'))),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplicate content reports the existing preview',
        (tester) async {
      final controller = _RecordingTemplateController(_SaveOutcome.duplicate);
      var started = false;
      await tester.pumpWidget(host(
        AssemblyCreatePage(
          initialConfig: _config(),
          onStartAdventure: (_) async => started = true,
        ),
        controller,
      ));
      await tester.pumpAndSettle();
      await openPhase4(tester);

      await tester.tap(find.byKey(const Key('assembly-save-preview-button')));
      await tester.pumpAndSettle();

      expect(started, isFalse);
      expect(find.text(l10n.adventurePreviewExistsMessage), findsOneWidget);
      expect(find.byType(AssemblyCreatePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('error keeps the save button usable and does not launch',
        (tester) async {
      final controller = _RecordingTemplateController(_SaveOutcome.error);
      var started = false;
      await tester.pumpWidget(host(
        AssemblyCreatePage(
          initialConfig: _config(),
          onStartAdventure: (_) async => started = true,
        ),
        controller,
      ));
      await tester.pumpAndSettle();
      await openPhase4(tester);

      await tester.tap(find.byKey(const Key('assembly-save-preview-button')));
      await tester.pumpAndSettle();

      expect(started, isFalse);
      expect(find.byKey(const Key('app-feedback-surface')), findsOneWidget);
      // Button recovered: not permanently disabled.
      final saveButton = tester.widget<OutlinedButton>(find.descendant(
        of: find.byKey(const Key('assembly-save-preview-button')),
        matching: find.byType(OutlinedButton),
      ));
      expect(saveButton.onPressed, isNotNull);
      expect(find.byType(AssemblyCreatePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AssemblyPreviewPage save preview', () {
    testWidgets('offers save and start together and saves without launching',
        (tester) async {
      final controller = _RecordingTemplateController(_SaveOutcome.saved);
      var started = false;
      await tester.pumpWidget(host(
        AssemblyPreviewPage(
          config: _config(),
          worldviewDesc: '迷雾笼罩的古老海域',
          onStartAdventure: (_) async => started = true,
        ),
        controller,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('assembly-preview-save-button')),
          findsOneWidget);
      expect(find.byKey(const Key('assembly-preview-start-button')),
          findsOneWidget);

      await tester.tap(find.byKey(const Key('assembly-preview-save-button')));
      await tester.pumpAndSettle();

      expect(controller.calls, hasLength(1));
      expect(controller.calls.single.worldviewDesc, '迷雾笼罩的古老海域');
      expect(started, isFalse);
      expect(find.byType(AssemblyPreviewPage), findsOneWidget);
      expect(find.text(l10n.adventurePreviewExistsMessage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('saved preview is restorable from the preset store', () {
    testWidgets('real persistence produces a restorable preview',
        (tester) async {
      // No controller override: exercises the real persistence authority.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: AssemblyCreatePage(
              initialConfig: _config(),
              onStartAdventure: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openPhase4(tester);

      await tester.tap(find.byKey(const Key('assembly-save-preview-button')));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }

      final container = ProviderScope.containerOf(
          tester.element(find.byType(AssemblyCreatePage)));
      final rows = await tester.runAsync(
          () => container.read(libraryRepoProvider).getAdventureTemplates());
      final previewRows = rows!
          .where((row) =>
              (row['id'] as String? ?? '').startsWith('assembly_preview_'))
          .toList();
      expect(previewRows, isNotEmpty);

      final controller = container.read(adventureTemplateControllerProvider);
      final preset = controller.buildPresetData(previewRows.first);
      expect(preset?.restoredConfig, isNotNull);
      final restored = preset!.restoredConfig!;
      expect(restored.worldview, '遗忘群岛');
      expect(restored.openingOptions, contains('拔剑固守船头'));
      expect(restored.selectedCharacters, isNotEmpty);
    });
  });

  group('bottom bar responsive and theming', () {
    for (final size in const <Size>[
      Size(320, 568),
      Size(375, 812),
      Size(600, 900),
      Size(960, 900),
      Size(1280, 900),
      Size(1440, 900),
    ]) {
      testWidgets('create phase 4 keeps save + start at ${size.width}px',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);
        final controller = _RecordingTemplateController(_SaveOutcome.saved);
        await tester.pumpWidget(host(
          AssemblyCreatePage(
            initialConfig: _config(),
            onStartAdventure: (_) async {},
          ),
          controller,
        ));
        await tester.pumpAndSettle();
        await openPhase4(tester);

        expect(find.byKey(const Key('assembly-save-preview-button')),
            findsOneWidget);
        expect(find.byKey(const Key('assembly-start-adventure-button')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('preview page keeps save + start at ${size.width}px',
          (tester) async {
        setViewport(tester, width: size.width, height: size.height);
        final controller = _RecordingTemplateController(_SaveOutcome.saved);
        await tester.pumpWidget(host(
          AssemblyPreviewPage(config: _config(), worldviewDesc: 'desc'),
          controller,
        ));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('assembly-preview-save-button')),
            findsOneWidget);
        expect(find.byKey(const Key('assembly-preview-start-button')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    for (final scale in const <double>[1.0, 1.5, 2.0]) {
      testWidgets('create phase 4 holds at ${scale}x text scale',
          (tester) async {
        setViewport(tester, width: 320, height: 568);
        final controller = _RecordingTemplateController(_SaveOutcome.saved);
        await tester.pumpWidget(host(
          AssemblyCreatePage(
            initialConfig: _config(),
            onStartAdventure: (_) async {},
          ),
          controller,
          textScale: scale,
        ));
        await tester.pumpAndSettle();
        await openPhase4(tester);
        expect(find.byKey(const Key('assembly-save-preview-button')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('holds up in dark theme', (tester) async {
      setViewport(tester, width: 1280, height: 900);
      final controller = _RecordingTemplateController(_SaveOutcome.saved);
      await tester.pumpWidget(host(
        AssemblyPreviewPage(config: _config(), worldviewDesc: 'desc'),
        controller,
        themeMode: ThemeMode.dark,
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('assembly-preview-save-button')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
