import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/generation_stage_progress.dart';
import 'package:lt_dialogue/models/generation_task_handle.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_detail_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/setting_card_fakes.dart';

/// Gateway that pauses one pass until the create/detail cancel button fires.
///
/// Only the two single-shot calls are implemented; everything else falls back
/// to [noSuchMethod], mirroring the shared fake. A cancelled request resolves
/// the gate with an error so the page exercises its cancellation path.
final class _GatedGenerationGateway implements LlmGateway {
  _GatedGenerationGateway({this.failure});

  final Object? failure;
  bool cancelRequested = false;

  @override
  bool get isConfigured => true;

  GenerationStageProgress get _progress => const GenerationStageProgress(
        stage: 1,
        totalStages: 3,
        stageName: '外貌与体态',
        currentCharacters: 120,
        targetCharacters: 5000,
      );

  Future<void> _pause(GenerationTaskHandle? taskHandle) async {
    final gate = Completer<void>();
    final registration = taskHandle?.registerCancel(() {
      cancelRequested = true;
      if (!gate.isCompleted) gate.completeError(StateError('cancelled'));
    });
    try {
      await gate.future;
    } finally {
      registration?.dispose();
    }
  }

  @override
  Future<Map<String, dynamic>> generateDetailedWorldview(
    String source, {
    int? targetTotalCharacters,
    void Function(WorldviewGenerationProgress progress)? onProgress,
    GenerationTaskHandle? taskHandle,
    void Function(GenerationStageProgress progress)? onStageProgress,
    dynamic generationMode,
  }) async {
    onProgress?.call(const WorldviewGenerationProgress(
      completedQuestions: 1,
      totalQuestions: 3,
      partialText: '概览',
      currentCharacters: 120,
      targetCharacters: 5000,
    ));
    onStageProgress?.call(_progress);
    final failure = this.failure;
    if (failure != null) throw failure;
    await _pause(taskHandle);
    return <String, dynamic>{'name': '星海大陆', 'description': '群星坠落之地。'};
  }

  @override
  Future<Map<String, dynamic>> generateDetailedResourceCharacter({
    required String source,
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    int? targetTotalCharacters,
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
    bool isNpc = false,
    GenerationTaskHandle? taskHandle,
    void Function(GenerationStageProgress progress)? onStageProgress,
    dynamic generationMode,
  }) async {
    onProgress?.call(1, 3, '外貌与体态');
    onStageProgress?.call(_progress);
    final failure = this.failure;
    if (failure != null) throw failure;
    await _pause(taskHandle);
    return <String, dynamic>{'name': '林恩', 'description': '游侠'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() isDone, {
  int maxIterations = 80,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (isDone()) return;
  }
}

void main() {
  testWidgets('detail page renders and saves at 320px', (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = const SettingCard(
      id: 'c1',
      kind: SettingCardKind.character,
      name: '林恩',
      summary: '游侠',
      content: '最初的设定',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardDetailPage(cardId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setting-card-name')), findsOneWidget);
    expect(find.byKey(const Key('setting-card-content')), findsOneWidget);
    expect(find.byKey(const Key('setting-card-save')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
        find.byKey(const Key('setting-card-content')), '更新后的设定');
    await tester.pump();
    // Entering text in the last field scrolls it into view, which moves the
    // action row off-screen; scroll back before tapping save.
    await tester.ensureVisible(find.byKey(const Key('setting-card-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-save')));
    await tester.pumpAndSettle();

    expect(repository.cards['c1']!.content, '更新后的设定');
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page writes a card at 320px', (tester) async {
    // Tall enough to keep the action row on screen; 320 is the width under test
    // for horizontal overflow.
    setViewport(tester, width: 320, height: 900);
    final repository = MemorySettingCardRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardCreatePage(
          mode: ResourceLibraryMode.adventure,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('setting-card-create-name')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
        find.byKey(const Key('setting-card-create-name')), '银月大陆');
    // The reference editor above the instruction field pushes the action row
    // below the 320px fold, so scroll it into view before tapping.
    await tester.tap(find.byKey(const Key('setting-card-create-manual')));
    await tester.pumpAndSettle();

    expect(repository.cards.values.single.name, '银月大陆');
    expect(repository.cards.values.single.mode, 'adventure');
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page forwards the detailed length target',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    final gateway = FakeSettingCardGateway(
      worldviewResponse: <String, dynamic>{
        'name': '星海大陆',
        'description': '群星坠落之地。',
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardCreatePage(mode: ResourceLibraryMode.adventure),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('setting-card-create-length-detailed')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('setting-card-create-instruction')),
      '写一个星海世界',
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();

    expect(gateway.targetCharacterArgs.last, 12000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail page restores the pre-generation snapshot',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = const SettingCard(
      id: 'c1',
      kind: SettingCardKind.character,
      name: '林恩',
      summary: '新摘要',
      content: '新正文',
      metadata: <String, Object?>{
        'previous_content_snapshot': <String, Object?>{
          'content': '旧正文',
          'summary': '旧摘要',
          'saved_at': '2026-01-01T00:00:00.000',
        },
      },
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardDetailPage(cardId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('setting-card-restore-previous')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester
        .ensureVisible(find.byKey(const Key('setting-card-restore-previous')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-restore-previous')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('恢复重生成前版本'),
    ));
    await tester.pumpAndSettle();

    expect(repository.cards['c1']!.content, '旧正文');
    expect(repository.cards['c1']!.summary, '旧摘要');
    expect(
      repository.cards['c1']!.metadata.containsKey('previous_content_snapshot'),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page forwards a custom length target', (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    final gateway = FakeSettingCardGateway(
      worldviewResponse: <String, dynamic>{
        'name': '星海大陆',
        'description': '群星坠落之地。',
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardCreatePage(mode: ResourceLibraryMode.adventure),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('setting-card-create-length-custom')),
    );
    await tester.pumpAndSettle();

    final customField =
        find.byKey(const Key('setting-card-create-length-custom-characters'));
    await tester.ensureVisible(customField);
    await tester.pumpAndSettle();
    await tester.enterText(customField, '7000');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(
      find.byKey(const Key('setting-card-create-instruction')),
      '写一个星海世界',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();

    expect(gateway.targetCharacterArgs.last, 7000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page blocks an out-of-range custom length',
      (tester) async {
    setViewport(tester, width: 320, height: 900);
    final repository = MemorySettingCardRepository();
    final gateway = FakeSettingCardGateway();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardCreatePage(mode: ResourceLibraryMode.adventure),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('setting-card-create-length-custom')),
    );
    await tester.pumpAndSettle();
    final customField =
        find.byKey(const Key('setting-card-create-length-custom-characters'));
    await tester.ensureVisible(customField);
    await tester.pumpAndSettle();
    await tester.enterText(customField, '500');
    await tester.pumpAndSettle();

    // The field explains the supported range before the form is submitted.
    expect(find.text('请输入 1000–50000 之间的目标字数'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('setting-card-create-instruction')),
      '写一个星海世界',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();

    expect(gateway.worldviewCalls, 0);
    expect(repository.cards, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generate dialog disables confirm for an unusable custom target',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = const SettingCard(
      id: 'c1',
      kind: SettingCardKind.worldview,
      name: '星海大陆',
      summary: '群星坠落之地。',
      content: '最初的设定',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );
    final gateway = FakeSettingCardGateway();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardDetailPage(cardId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('setting-card-generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-generate')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('setting-card-length-custom')));
    await tester.pumpAndSettle();
    final customField =
        find.byKey(const Key('setting-card-length-custom-characters'));
    await tester.ensureVisible(customField);
    await tester.pumpAndSettle();
    await tester.enterText(customField, '30000');
    await tester.pumpAndSettle();

    FilledButton confirm() => tester.widget<FilledButton>(
          find.byKey(const Key('setting-card-generate-confirm')),
        );
    // A worldview accepts 30,000, so confirm stays usable.
    expect(confirm().onPressed, isNotNull);

    await tester.enterText(customField, '200');
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('character create page uses the smaller detailed target',
      (tester) async {
    setViewport(tester, width: 320, height: 900);
    final repository = MemorySettingCardRepository();
    final gateway = FakeSettingCardGateway(
      characterResponse: <String, dynamic>{'name': '林恩', 'description': '游侠'},
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardCreatePage(
          initialType: ResourceType.character,
          mode: ResourceLibraryMode.adventure,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('setting-card-create-length-detailed')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('setting-card-create-instruction')),
      '写一个游侠',
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();

    // 5,000 sits in the 4,000–6,000 band used for character cards, instead of
    // the worldview's 12,000.
    expect(gateway.targetCharacterArgs.last, 5000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page shows stage progress and cancels', (tester) async {
    setViewport(tester, width: 320, height: 900);
    final repository = MemorySettingCardRepository();
    final gateway = _GatedGenerationGateway();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Character generation is the path that forwards the task handle to the
        // gateway, so it is the one that can be cancelled mid-flight.
        home: SettingCardCreatePage(
          initialType: ResourceType.character,
          mode: ResourceLibraryMode.adventure,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('setting-card-create-instruction')),
      '写一个星海世界',
    );
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-ai')));
    await tester.pump();

    String? progressText() {
      final finder = find.byKey(const Key('setting-card-create-progress'));
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<Text>(finder).data;
    }

    await _pumpUntil(
      tester,
      () => (progressText() ?? '').contains('外貌与体态'),
    );
    expect(progressText(), contains('外貌与体态'));
    expect(progressText(), contains('120 / 5000'));

    // The progress row sits below the fold at 320×900; scroll it into view.
    await tester.ensureVisible(
      find.byKey(const Key('setting-card-create-cancel')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('setting-card-create-cancel')));
    await _pumpUntil(
      tester,
      () => find.text('已取消生成，可继续编辑').evaluate().isNotEmpty,
    );

    expect(gateway.cancelRequested, isTrue);
    // Cancellation returns to the editable form with neutral copy, and the
    // empty draft is discarded instead of lingering in the library.
    expect(find.text('已取消生成，可继续编辑'), findsOneWidget);
    expect(find.byKey(const Key('setting-card-create-name')), findsOneWidget);
    expect(repository.cards.values.where((c) => !c.isDeleted), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail page shows stage progress and cancels', (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = const SettingCard(
      id: 'c1',
      kind: SettingCardKind.character,
      name: '星海大陆',
      summary: '群星坠落之地。',
      content: '最初的设定',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );
    final gateway = _GatedGenerationGateway();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardDetailPage(cardId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('setting-card-generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-generate-confirm')));
    await tester.pump();

    String? progressText() {
      final finder = find.byKey(const Key('setting-card-generate-progress'));
      if (finder.evaluate().isEmpty) return null;
      return tester.widget<Text>(finder).data;
    }

    await _pumpUntil(
      tester,
      () => (progressText() ?? '').contains('外貌与体态'),
    );
    expect(progressText(), contains('外貌与体态'));
    expect(progressText(), contains('120 / 5000'));

    await tester.ensureVisible(
      find.byKey(const Key('setting-card-generate-cancel')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('setting-card-generate-cancel')));
    await _pumpUntil(
      tester,
      () => find.text('已取消生成，可继续编辑').evaluate().isNotEmpty,
    );

    expect(gateway.cancelRequested, isTrue);
    expect(find.text('已取消生成，可继续编辑'), findsOneWidget);
    expect(repository.cards['c1']!.content, '最初的设定');
    expect(
      tester
          .widget<OutlinedButton>(
              find.byKey(const Key('setting-card-generate')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail page hides raw JSON in generation errors',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = const SettingCard(
      id: 'c1',
      kind: SettingCardKind.worldview,
      name: '星海大陆',
      summary: '群星坠落之地。',
      content: '最初的设定',
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
    );
    final gateway = _GatedGenerationGateway(
      failure: const SettingCardGenerationException(
        '生成失败 {"raw_json":"secret"}',
      ),
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        settingCardRepositoryProvider.overrideWithValue(repository),
        llmGatewayProvider.overrideWithValue(gateway),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingCardDetailPage(cardId: 'c1'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('setting-card-generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-generate-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('raw_json'), findsNothing);
    expect(find.textContaining('{'), findsNothing);
    // The readable part of the typed message survives the scrub.
    expect(find.text('生成失败'), findsOneWidget);
    expect(repository.cards['c1']!.content, '最初的设定');
    expect(tester.takeException(), isNull);
  });
}
