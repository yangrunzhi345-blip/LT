import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/controllers/adventure_setup_controller.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/library_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

/// Forces [isKeyConfigured] so the Wizard reaches its persistence/assembly
/// steps without touching secure storage or a live provider.
class _KeyConfiguredChatProvider extends ChatProvider {
  _KeyConfiguredChatProvider()
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
}

/// A repository that still loads normally but fails one write, so the Wizard's
/// start boundary is exercised on a real production code path.
class _FailingWriteRepo extends LibraryRepositoryImpl {
  _FailingWriteRepo({required super.getDb, this.failCharacters = false});

  final bool failCharacters;

  @override
  Future<void> saveCharacterCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    String weight = '',
    String contentHash = '',
    String authoringMethod = '',
    String aiGenerationDepth = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    if (failCharacters) throw StateError('character-save-boom');
    return super.saveCharacterCard(
      id: id,
      name: name,
      jsonData: jsonData,
      source: source,
      now: now,
      matchingWorldviewId: matchingWorldviewId,
      weight: weight,
      contentHash: contentHash,
      authoringMethod: authoringMethod,
      aiGenerationDepth: aiGenerationDepth,
      mode: mode,
    );
  }
}

/// Throws from the worldview save orchestration itself (the repository swallows
/// nothing here), so the boundary must cover the persistence step.
class _ThrowingCrudController extends ResourceCrudController {
  _ThrowingCrudController(ILibraryRepository repository)
      : super(repository: repository);

  @override
  Future<ResourceOperationResult> saveWorldviewPreset({
    required String id,
    required String name,
    required String description,
    required String entriesJson,
    required String now,
    String source = '',
    String contentHash = '',
    String detailJson = '{}',
    bool validate = true,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    throw StateError('worldview-save-boom');
  }
}

class _ThrowingSetupController extends AdventureSetupController {
  @override
  Future<void> loadInitialData() async {
    throw StateError('load-initial-boom');
  }
}

/// In-memory replacements so the start boundary can be exercised without the
/// real sqlite/file async: widget test bodies run under FakeAsync, where awaited
/// database work never completes. Each override keeps the same observable
/// contract as production (success/throw) but resolves on a microtask.
class _NoopSetupController extends AdventureSetupController {
  @override
  Future<void> loadInitialData() async {}
}

class _NoopCrudController extends ResourceCrudController {
  _NoopCrudController(ILibraryRepository repository)
      : super(repository: repository);

  @override
  Future<ResourceOperationResult> saveWorldviewPreset({
    required String id,
    required String name,
    required String description,
    required String entriesJson,
    required String now,
    String source = '',
    String contentHash = '',
    String detailJson = '{}',
    bool validate = true,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const ResourceOperationResult.success();
}

class _NoopRepo extends LibraryRepositoryImpl {
  _NoopRepo({required super.getDb});

  @override
  Future<void> saveCharacterCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    String weight = '',
    String contentHash = '',
    String authoringMethod = '',
    String aiGenerationDepth = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {}
}

class _NoopLibraryProvider extends LibraryProvider {
  _NoopLibraryProvider()
      : super(
          libraryRepo:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
        );

  @override
  Future<void> loadCharacterCards() async {}
}

AdventureConfig _configWithSupportingCustomAttributes() {
  return AdventureConfig(
    name: '主角',
    selectedCharacters: [
      AdventureSelectedCharacter(
        id: 'p1',
        characterId: 'p1',
        characterName: '主角',
        isProtagonist: true,
        narrativeRole: AdventureCharacterRole.protagonist,
        sortOrder: 0,
        characterCardJson: {'name': '主角'},
      ),
      AdventureSelectedCharacter(
        id: 's1',
        characterId: 's1',
        characterName: '配角',
        isProtagonist: false,
        narrativeRole: AdventureCharacterRole.supporting,
        sortOrder: 1,
        // Malformed custom attribute value: assembly must fail inside the
        // boundary instead of throwing an uncaught TypeError.
        characterCardJson: {
          'name': '配角',
          'custom_attributes': ['not-a-map'],
        },
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    // SettingsProvider subscribes to connectivity_plus. flutter_test has no
    // platform implementation, and the real async drained by runAsync would
    // otherwise surface a MissingPluginException as a test failure.
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
    tempDir = await Directory.systemTemp.createTemp('lt_p0_start_test_');
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

  /// Pumps virtual frames until [isDone] holds. The Wizard's persistence is
  /// replaced by in-memory overrides (see the fakes above), so its async work
  /// resolves on microtasks and this never depends on a fixed duration.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() isDone, {
    int maxIterations = 20,
  }) async {
    for (var i = 0; i < maxIterations; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (isDone()) return;
    }
  }

  Future<void> pumpWizard(
    WidgetTester tester, {
    required Future<void> Function(AdventureConfig config) onStart,
    AdventureConfig? initialConfig,
    ResourceCrudController Function()? crud,
    AdventureSetupController Function()? setup,
    ILibraryRepository Function()? repo,
  }) async {
    // A tall viewport keeps the Wizard's controls inside the lazy ListView so
    // they are actually built; the default 800x600 pushes them below the fold
    // once _loadData populates the step content.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // The Wizard short-circuits to the API settings dialog when no key is
    // configured, which would hide the start-boundary behaviour under test.
    // Every dependency that would otherwise await real sqlite/file I/O is
    // replaced in memory; a test can inject a throwing/failing variant for the
    // dependency whose failure it exercises.
    final allOverrides = <Object>[
      chatProvider.overrideWith((ref) => _KeyConfiguredChatProvider()),
      libraryProvider.overrideWith((ref) => _NoopLibraryProvider()),
      resourceCrudControllerProvider.overrideWith((ref) =>
          crud?.call() ??
          _NoopCrudController(
              LibraryRepositoryImpl(getDb: () => DatabaseService.database))),
      adventureSetupControllerProvider
          .overrideWith((ref) => setup?.call() ?? _NoopSetupController()),
      libraryRepoProvider.overrideWithValue(
          repo?.call() ?? _NoopRepo(getDb: () => DatabaseService.database)),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: allOverrides.cast(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AdventureWizardScreen(
                          onStartAdventure: onStart,
                          // A protagonist must exist or _handleStart returns
                          // before reaching the persistence/assembly steps.
                          initialConfig:
                              initialConfig ?? AdventureConfig(name: '主角'),
                        ),
                      ),
                    );
                  },
                  child: const Text('打开向导'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开向导'));
    await tester.pump();
    // Let the Wizard's post-frame _loadData settle before interacting.
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  /// Advances to the final step and taps the start button. The submit spinner is
  /// the observable completion signal: it appears while `_handleStart` runs and
  /// clears in `finally`, so we wait for it to disappear rather than guessing a
  /// duration.
  Future<void> startAdventure(WidgetTester tester) async {
    final stepper = tester.widget<Stepper>(find.byType(Stepper));
    stepper.onStepTapped!(4);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('踏入冒险'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
    // Let the SnackBar entrance transition settle: ScaffoldMessenger briefly
    // renders the outgoing/incoming SnackBar together, so a short pump would
    // see two identical error texts.
    await tester.pump(const Duration(milliseconds: 600));
  }

  void expectRecovered(WidgetTester tester, String messageFragment) {
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('启动场景失败'), findsOneWidget);
    expect(find.textContaining(messageFragment), findsOneWidget);
    // The submit spinner is gone and the action button is usable again.
    expect(find.text('踏入冒险'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(AdventureWizardScreen), findsOneWidget);
  }

  testWidgets('onStartAdventure failure resets submitting and allows a retry',
      (tester) async {
    var calls = 0;
    await pumpWizard(
      tester,
      onStart: (_) async {
        calls++;
        throw StateError('start-callback-boom');
      },
    );

    await startAdventure(tester);
    expectRecovered(tester, 'start-callback-boom');
    expect(calls, 1);

    // A second attempt must be possible: the guard is no longer stuck.
    await startAdventure(tester);
    expect(calls, 2);
  });

  testWidgets('character save failure is caught before navigation',
      (tester) async {
    var calls = 0;
    await pumpWizard(
      tester,
      onStart: (_) async => calls++,
      repo: () => _FailingWriteRepo(
        getDb: () => DatabaseService.database,
        failCharacters: true,
      ),
    );

    await startAdventure(tester);
    expectRecovered(tester, 'character-save-boom');
    expect(calls, 0);
  });

  testWidgets('worldview save failure is caught', (tester) async {
    var calls = 0;
    await pumpWizard(
      tester,
      onStart: (_) async => calls++,
      crud: () => _ThrowingCrudController(
          LibraryRepositoryImpl(getDb: () => DatabaseService.database)),
    );

    await startAdventure(tester);
    expectRecovered(tester, 'worldview-save-boom');
    expect(calls, 0);
  });

  testWidgets('loadInitialData failure is caught', (tester) async {
    var calls = 0;
    await pumpWizard(
      tester,
      onStart: (_) async => calls++,
      setup: () => _ThrowingSetupController(),
    );

    await startAdventure(tester);
    expectRecovered(tester, 'load-initial-boom');
    expect(calls, 0);
  });

  testWidgets('domain assembly failure is caught and never navigates',
      (tester) async {
    var calls = 0;
    await pumpWizard(
      tester,
      onStart: (_) async => calls++,
      initialConfig: _configWithSupportingCustomAttributes(),
    );

    await startAdventure(tester);
    expect(find.textContaining('启动场景失败'), findsOneWidget);
    expect(find.text('踏入冒险'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(AdventureWizardScreen), findsOneWidget);
    expect(calls, 0);
  });
}
