import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/resource_library/edit_drafts.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/screens/resource_library/character_card_edit_page.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';

import '../helpers/responsive_test_helper.dart';

const _saveActionKey = Key('character-card-save-action');

Finder _fieldByLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'TextField with label="$label"',
    );

Finder _actionLabel(String label) => find.descendant(
      of: find.byKey(_saveActionKey),
      matching: find.text(label),
    );

/// A controller whose save always fails, to prove a refused write never fakes
/// success and keeps the form dirty.
final class _FailingCrud extends ResourceCrudController {
  _FailingCrud()
      : super(
          repository:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
        );

  @override
  Future<ResourceOperationResult> saveCharacterCardDraft(
    CharacterCardEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async =>
      const ResourceOperationResult.failure('磁盘写入失败');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  final zh = lookupAppLocalizations(const Locale('zh'));
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_character_save_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var attempt = 0; attempt < 200; attempt++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
      if (finder.evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 150));
        return;
      }
    }
    expect(finder, findsWidgets);
  }

  Future<List<Map<String, dynamic>>> loadCards(WidgetTester tester) async {
    final repo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
    return await tester.runAsync(
          () => repo.getCharacterCards(mode: ResourceLibraryMode.adventure),
        ) ??
        const <Map<String, dynamic>>[];
  }

  Widget app({
    Widget child = const SizedBox.shrink(),
    Locale locale = const Locale('zh'),
    List<Object> overrides = const <Object>[],
  }) {
    return ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: child,
      ),
    );
  }

  testWidgets('the character editor exposes a Save action', (tester) async {
    setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(app(child: const CharacterCardEditPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(_saveActionKey), findsOneWidget);
    expect(_actionLabel(zh.saveAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creating a character persists through the toolbar Save',
      (tester) async {
    setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(app(child: const CharacterCardEditPage()));
    await tester.pumpAndSettle();

    await tester.enterText(
        _fieldByLabel('${zh.characterNameLabel} *'), '测试角色甲');
    await tester.enterText(_fieldByLabel(zh.personalityLabel), '冷静');
    await tester.enterText(_fieldByLabel(zh.relationsNoteLabel), '与林恩是同伴');
    await tester.pump();

    expect(_actionLabel(zh.saveAction), findsOneWidget,
        reason: 'an edited form returns to the Save state');

    await tester.tap(find.byKey(_saveActionKey));
    await waitFor(tester, _actionLabel(zh.savedAction));

    // The toolbar save must not leave the page.
    expect(find.byType(CharacterCardEditPage), findsOneWidget);

    final cards = await loadCards(tester);
    final saved = cards.firstWhere((card) => card['name'] == '测试角色甲');
    final envelope =
        jsonDecode(saved['json_data'] as String) as Map<String, dynamic>;
    final data = envelope['data'] as Map<String, dynamic>;
    expect(data['personality'], '冷静');
    expect((data['world_profile'] as Map)['relationship_notes'], '与林恩是同伴');
    expect(saved['matching_worldview_id'], '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing an existing character preserves relations and fields',
      (tester) async {
    setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(app(child: const CharacterCardEditPage()));
    await tester.pumpAndSettle();
    await tester.enterText(
        _fieldByLabel('${zh.characterNameLabel} *'), '测试角色乙');
    await tester.enterText(_fieldByLabel(zh.relationsNoteLabel), '旧关系');
    await tester.pump();
    await tester.tap(find.byKey(_saveActionKey));
    await waitFor(tester, _actionLabel(zh.savedAction));

    final created =
        (await loadCards(tester)).firstWhere((card) => card['name'] == '测试角色乙');
    final id = created['id'] as String;

    await tester.pumpWidget(app(
      child: CharacterCardEditPage(existingId: id, existingCard: created),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(_fieldByLabel(zh.personalityLabel), '温和');
    await tester.enterText(_fieldByLabel(zh.relationsNoteLabel), '林恩的挚友');
    await tester.pump();
    await tester.tap(find.byKey(_saveActionKey));
    await waitFor(tester, _actionLabel(zh.savedAction));

    final cards = await loadCards(tester);
    final saved = cards.firstWhere((card) => card['id'] == id);
    final envelope =
        jsonDecode(saved['json_data'] as String) as Map<String, dynamic>;
    final data = envelope['data'] as Map<String, dynamic>;
    expect(data['personality'], '温和');
    expect((data['world_profile'] as Map)['relationship_notes'], '林恩的挚友',
        reason: 'the relationship field must survive a manual save');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed save keeps a dirty, retryable state', (tester) async {
    setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(app(
      child: const CharacterCardEditPage(),
      overrides: [
        resourceCrudControllerProvider.overrideWith((ref) => _FailingCrud()),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        _fieldByLabel('${zh.characterNameLabel} *'), '保存会失败');
    await tester.pump();
    await tester.tap(find.byKey(_saveActionKey));
    await tester.pumpAndSettle();

    expect(_actionLabel(zh.saveFailedAction), findsOneWidget);
    expect(_actionLabel(zh.savedAction), findsNothing);
    // The form stays open so the user can fix and retry.
    expect(find.byType(CharacterCardEditPage), findsOneWidget);
    expect(find.text('保存会失败'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Save action fits a 320 px viewport', (tester) async {
    setViewport(tester, width: 320, height: 568);
    await tester.pumpWidget(app(child: const CharacterCardEditPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(_saveActionKey), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.byType(IconButton)),
      findsOneWidget,
    );
    expect(find.byTooltip(zh.saveAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Save action is localized in English', (tester) async {
    setViewport(tester, width: 800, height: 800);
    await tester.pumpWidget(app(
      child: const CharacterCardEditPage(),
      locale: const Locale('en'),
    ));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.text('Save')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
