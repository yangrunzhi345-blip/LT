import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_reference_input.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_create_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/setting_card_detail_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/widgets/setting_card_reference_editor.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/setting_card_fakes.dart';

void main() {
  testWidgets('paste mode is default and the counter follows input at 320px',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    await _pumpEditor(tester, repository: MemorySettingCardRepository());

    expect(
        find.byKey(const Key('setting-card-reference-paste')), findsOneWidget);
    expect(find.text('已输入 0 / 8000 字'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(
        find.byKey(const Key('setting-card-reference-paste')), '你好');
    await tester.pump();

    expect(find.text('已输入 2 / 8000 字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching modes reveals the matching inputs', (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = _card;
    await _pumpEditor(tester, repository: repository);

    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setting-card-reference-file-name')),
        findsOneWidget);
    expect(find.byKey(const Key('setting-card-reference-file-content')),
        findsOneWidget);

    await tester.tap(find.text('已有卡'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('setting-card-reference-existing')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('over-limit text shows the truncation warning', (tester) async {
    setViewport(tester, width: 320, height: 568);
    await _pumpEditor(tester, repository: MemorySettingCardRepository());

    await tester.enterText(
      find.byKey(const Key('setting-card-reference-paste')),
      'x' * 8001,
    );
    await tester.pump();

    expect(find.text('超过 8000 字，生成时按相关度截取'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mode switches keep every mode input', (tester) async {
    setViewport(tester, width: 320, height: 568);
    await _pumpEditor(tester, repository: MemorySettingCardRepository());

    await tester.enterText(
        find.byKey(const Key('setting-card-reference-paste')), '保留文本');
    await tester.pump();

    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('保留文本'), findsNothing);

    await tester.tap(find.text('粘贴'));
    await tester.pumpAndSettle();
    expect(find.text('保留文本'), findsOneWidget);
    expect(find.textContaining('paste:保留文本'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create page forwards pasted reference into generation',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    final gateway = FakeSettingCardGateway(
      worldviewResponse: const <String, dynamic>{'description': '生成的正文'},
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
        home: SettingCardCreatePage(),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('setting-card-create-name')), '银月大陆');
    await tester.enterText(
        find.byKey(const Key('setting-card-create-instruction')), '写一段设定');
    await tester.enterText(
      find.byKey(const Key('setting-card-reference-paste')),
      'LUNA-REF-1234 的参考材料',
    );
    await tester.pump();

    await tester.ensureVisible(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('setting-card-create-ai')));
    await tester.pumpAndSettle();

    expect(gateway.sources, isNotEmpty);
    expect(gateway.sources.last, contains('LUNA-REF-1234'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail generation forwards pasted reference', (tester) async {
    setViewport(tester, width: 320, height: 568);
    final repository = MemorySettingCardRepository();
    repository.cards['c1'] = _card;
    final gateway = FakeSettingCardGateway(
      characterResponse: const <String, dynamic>{'description': '生成的正文'},
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

    await tester.enterText(
        find.byKey(const Key('setting-card-generate-instruction')), '扩写角色');
    await tester.enterText(
      find.byKey(const Key('setting-card-reference-paste')),
      'DETAIL-REF-5678',
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('setting-card-generate-confirm')));
    await tester.pumpAndSettle();

    expect(gateway.sources, isNotEmpty);
    expect(gateway.sources.last, contains('DETAIL-REF-5678'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px with a 2x text scale still lays out the mode picker',
      (tester) async {
    setViewport(tester, width: 320, height: 568);
    await _pumpEditor(
      tester,
      repository: MemorySettingCardRepository(),
      textScale: 2,
    );

    expect(
        find.byKey(const Key('setting-card-reference-mode')), findsOneWidget);
    expect(find.text('粘贴'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('已有卡'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file content shows the same character counter', (tester) async {
    setViewport(tester, width: 320, height: 568);
    await _pumpEditor(tester, repository: MemorySettingCardRepository());

    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('setting-card-reference-file-content')),
      '文件名内容',
    );
    await tester.pump();

    expect(find.text('已输入 5 / 8000 字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const SettingCard _card = SettingCard(
  id: 'c1',
  kind: SettingCardKind.character,
  name: '林恩',
  summary: '游侠',
  content: '最初的设定',
  createdAt: '2026-01-01T00:00:00.000',
  updatedAt: '2026-01-01T00:00:00.000',
);

Future<void> _pumpEditor(
  WidgetTester tester, {
  required MemorySettingCardRepository repository,
  double textScale = 1,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingCardRepositoryProvider.overrideWithValue(repository),
      llmGatewayProvider.overrideWithValue(FakeSettingCardGateway()),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: _EditorHarness(),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

final class _EditorHarness extends StatefulWidget {
  const _EditorHarness();

  @override
  State<_EditorHarness> createState() => _EditorHarnessState();
}

final class _EditorHarnessState extends State<_EditorHarness> {
  SettingCardReferenceMode _mode = SettingCardReferenceMode.paste;
  SettingCardReferenceInput? _reference;

  @override
  Widget build(BuildContext context) {
    final reference = _reference;
    final label = reference == null
        ? 'null'
        : '${reference.mode.name}:${reference.text}:${reference.sourceCardId}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingCardReferenceEditor(
          mode: _mode,
          onModeChanged: (mode) => setState(() => _mode = mode),
          onChanged: (value) => setState(() => _reference = value),
        ),
        Text(label, key: const Key('editor-reference-state')),
      ],
    );
  }
}
