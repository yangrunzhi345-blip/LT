import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/character_relationship_management.dart';
import 'package:lt_dialogue/domain/resources/character_relationship.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/widgets/character_step/character_roster_panel.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/character_relationship_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/setting_card_fakes.dart';

/// Empty legacy tables: this test only needs the card store, so the setup
/// controller must not wait on a real SQLite open inside fake-async pumps.
class _EmptyLibraryRepository implements ILibraryRepository {
  @override
  Future<List<Map<String, dynamic>>> getCharacterCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> getNpcCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  Future<List<Map<String, dynamic>>> getWorldviewPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const <Map<String, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Empty relationship store: the card editor renders the relationships
/// section, and a real DB read would keep its spinner animating inside the
/// fake-async test.
class _EmptyRelationshipRepository implements CharacterRelationshipRepository {
  @override
  Future<List<CharacterRelationship>> listForResource(
    ResourceId resourceId,
  ) async =>
      const <CharacterRelationship>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Forces [isKeyConfigured] so the wizard reaches generation without touching
/// secure storage or a live provider.
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

/// [FakeSettingCardGateway] with an optional manual gate on the worldview pass.
///
/// The shared fake is final and cannot be extended, so the pause is layered on
/// by delegation: recording and the canned answer still come from it.
class _GatedWorldviewGateway implements LlmGateway {
  _GatedWorldviewGateway({this.paused = true})
      : _inner = FakeSettingCardGateway();

  final FakeSettingCardGateway _inner;
  final bool paused;
  Completer<void>? _gate;

  set worldviewResponse(Map<String, dynamic> response) =>
      _inner.worldviewResponse = response;

  set characterResponse(Map<String, dynamic> response) =>
      _inner.characterResponse = response;

  List<int?> get targetCharacterArgs => _inner.targetCharacterArgs;

  /// Completes the pending worldview pass; only valid while [paused].
  Completer<void> get gate => _gate!;

  @override
  bool get isConfigured => _inner.isConfigured;

  @override
  Future<Map<String, dynamic>> generateDetailedWorldview(
    String source, {
    int? targetTotalCharacters,
    void Function(WorldviewGenerationProgress progress)? onProgress,
    dynamic generationMode,
  }) async {
    onProgress?.call(const WorldviewGenerationProgress(
      completedQuestions: 1,
      totalQuestions: 2,
      partialText: '阶段一',
    ));
    if (paused) {
      final gate = _gate = Completer<void>();
      await gate.future;
    }
    return _inner.generateDetailedWorldview(
      source,
      targetTotalCharacters: targetTotalCharacters,
      generationMode: generationMode,
    );
  }

  @override
  Future<Map<String, dynamic>> generateDetailedResourceCharacter({
    required String source,
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    int? targetTotalCharacters,
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
    dynamic generationMode,
  }) =>
      _inner.generateDetailedResourceCharacter(
        source: source,
        worldview: worldview,
        associatedCharacters: associatedCharacters,
        targetTotalCharacters: targetTotalCharacters,
        onProgress: onProgress,
        generationMode: generationMode,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'openai_api_key': 'test',
      'deepseek_api_key': 'test',
    });
    tempDir = await Directory.systemTemp.createTemp('lt_wizard_autofill_');
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

  /// Pumps virtual frames until [isDone] holds. Only the LLM gateway is faked:
  /// the card repository, the setup controller and the wizard are the production
  /// implementations, so completion is the in-memory sqlite work landing.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() isDone, {
    int maxIterations = 120,
  }) async {
    for (var i = 0; i < maxIterations; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (isDone()) return;
    }
  }

  Future<MemorySettingCardRepository> pumpWizard(
    WidgetTester tester,
    LlmGateway gateway,
  ) async {
    // A tall viewport keeps the whole step laid out inside the Stepper, so its
    // controls are built and tappable.
    setViewport(tester, width: 1200, height: 2600);

    final cards = MemorySettingCardRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatProvider.overrideWith((ref) => _KeyConfiguredChatProvider()),
          // Card storage is independent of the wizard's launch flow; an
          // in-memory repository keeps this test focused on generation state
          // instead of waiting on the SQLite open path. Both the service and
          // the setup controller must see the same store, otherwise a freshly
          // generated card never reaches the wizard lists.
          settingCardRepositoryProvider.overrideWithValue(cards),
          libraryRepoProvider.overrideWithValue(_EmptyLibraryRepository()),
          characterRelationshipManagementProvider.overrideWithValue(
            CharacterRelationshipManagement(_EmptyRelationshipRepository()),
          ),
          settingCardServiceProvider.overrideWith(
            (ref) => SettingCardService(
              repository: cards,
              gateway: gateway,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AdventureWizardScreen(onStartAdventure: (_) async {}),
        ),
      ),
    );
    await tester.pump();
    // The wizard loads its library in a post-frame callback; wait for the load
    // indicator to disappear rather than guessing a duration.
    await pumpUntil(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    return cards;
  }

  testWidgets(
      'worldview AI generation selects the card and backfills name and description',
      (tester) async {
    final gateway = _GatedWorldviewGateway()
      ..worldviewResponse = <String, dynamic>{
        'name': '星海大陆',
        'description': '一片漂浮于星海的大陆',
        'modules': <String, dynamic>{
          'history': '三百年前的星陨战争',
        },
      };
    final cards = await pumpWizard(tester, gateway);

    expect(find.text('开始 AI 自动编写'), findsOneWidget);
    await tester.tap(find.text('开始 AI 自动编写'));
    await tester.pump();
    // In flight: the entry point is disabled and reports progress while the
    // gateway is still holding the answer.
    await pumpUntil(tester, () => find.text('1 / 2').evaluate().isNotEmpty);
    expect(find.text('正在构思世界观…'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    final generatingButton = tester.widget<FilledButton>(
      find
          .ancestor(
            of: find.text('正在构思世界观…'),
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect(generatingButton.onPressed, isNull);

    gateway.gate.complete();
    await pumpUntil(
      tester,
      () => find.text('重新生成世界观').evaluate().isNotEmpty,
    );
    await tester.pump();

    // The generated card is selected in the worldview chip row ...
    final chipFinder = find.widgetWithText(ChoiceChip, '星海大陆');
    expect(chipFinder, findsOneWidget);
    expect(tester.widget<ChoiceChip>(chipFinder).selected, isTrue);
    // ... and its title and description are backfilled into the editor fields.
    expect(find.text('星海大陆'), findsWidgets);
    expect(find.text('一片漂浮于星海的大陆'), findsOneWidget);
    // Progress is cleared once the pass finishes.
    expect(find.text('1 / 2'), findsNothing);
    // Concise mode is the default, so no long-form target is requested.
    expect(gateway.targetCharacterArgs.single, isNull);
    expect(tester.takeException(), isNull);

    // Advancing must not re-save the generated card through the legacy preset
    // path, which would create a res_legacy_* mirror next to it.
    final stepper = tester.widget<Stepper>(find.byType(Stepper));
    stepper.onStepContinue!();
    await tester.pumpAndSettle();
    expect(cards.cards, hasLength(1));
    expect(cards.cards.keys.single.startsWith('res_legacy_'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detailed mode is what requests the long-form character target',
      (tester) async {
    final gateway = _GatedWorldviewGateway(paused: false)
      ..worldviewResponse = <String, dynamic>{
        'name': '星海大陆',
        'description': '一片漂浮于星海的大陆',
      };
    await pumpWizard(tester, gateway);

    await tester.tap(find.text('详细模式'));
    await tester.pump();

    await tester.tap(find.text('开始 AI 自动编写'));
    await pumpUntil(
      tester,
      () => find.text('重新生成世界观').evaluate().isNotEmpty,
    );

    expect(gateway.targetCharacterArgs.single, 12000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('character AI generation joins the roster as the protagonist',
      (tester) async {
    final gateway = _GatedWorldviewGateway(paused: false)
      ..characterResponse = <String, dynamic>{
        'name': '林恩',
        'description': '游侠',
        'personality': '冷静',
      };
    await pumpWizard(tester, gateway);

    // Step 2 (characters): the roster is empty, so the entry point offers the
    // protagonist generation label.
    final stepper = tester.widget<Stepper>(find.byType(Stepper));
    stepper.onStepTapped!(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('开始 AI 自动生成主角'), findsOneWidget);
    await tester.tap(find.text('开始 AI 自动生成主角'));
    await pumpUntil(
      tester,
      () => find
          .descendant(
            of: find.byType(WizardCharacterRosterPanel),
            matching: find.text('林恩'),
          )
          .evaluate()
          .isNotEmpty,
    );

    final roster = find.byType(WizardCharacterRosterPanel);
    expect(
        find.descendant(of: roster, matching: find.text('林恩')), findsOneWidget);
    // The first generated character becomes the one protagonist badge.
    expect(find.descendant(of: roster, matching: find.text('主控主角')),
        findsOneWidget);
    // The roster is no longer empty, so the panel switches to the add label.
    expect(find.text('使用 AI 增添阵容角色'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Editing a card-backed roster member opens the card editor and the new
    // name is reflected in the roster after returning.
    await tester.tap(find.descendant(
      of: roster,
      matching: find.byTooltip('编辑'),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setting-card-name')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('setting-card-name')),
      '林恩·改',
    );
    await tester.ensureVisible(find.byKey(const Key('setting-card-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-save')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: roster, matching: find.text('林恩·改')),
      findsOneWidget,
    );

    // Deleting the card removes the roster row instead of leaving a ghost.
    await tester.tap(find.descendant(
      of: roster,
      matching: find.byTooltip('编辑'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('删除'),
    ));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: roster, matching: find.text('林恩·改')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
