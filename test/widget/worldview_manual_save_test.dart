import 'dart:async';
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
import 'package:lt_dialogue/screens/resource_library/worldview_tab.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';

import '../helpers/responsive_test_helper.dart';

const _saveActionKey = Key('worldview-save-action');
const _openKey = Key('open-worldview-editor');

/// Simple-mode worldviews must have a 200–500 character description.
final String _descriptionA = '测试世界观描述段落，' * 24;
final String _descriptionB = '更新后的世界观描述，' * 24;

Finder _fieldByLabel(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
      description: 'TextField with label="$label"',
    );

Finder _actionLabel(String label) => find.descendant(
      of: find.byKey(_saveActionKey),
      matching: find.text(label),
    );

/// A crud controller whose worldview save can be gated or forced to fail, to
/// prove the toolbar loading/duplicate/failure behaviour without touching the
/// real write path.
final class _RecordingCrud extends ResourceCrudController {
  _RecordingCrud()
      : super(
          repository:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
        );

  int saveCalls = 0;
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<ResourceOperationResult> saveWorldviewDraft(
    WorldviewEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    saveCalls++;
    final waiting = gate;
    if (waiting != null) {
      await waiting.future;
      gate = null;
    }
    if (fail) return const ResourceOperationResult.failure('磁盘写入失败');
    return const ResourceOperationResult.success();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  final zh = lookupAppLocalizations(const Locale('zh'));
  late Directory tempDir;
  Map<String, dynamic>? launchExisting;

  setUp(() async {
    launchExisting = null;
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_worldview_save_');
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

  Future<List<Map<String, dynamic>>> loadWorldviews(WidgetTester tester) async {
    final repo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
    return await tester.runAsync(
          () => repo.getWorldviewPresets(mode: ResourceLibraryMode.adventure),
        ) ??
        const <Map<String, dynamic>>[];
  }

  Widget app({
    Locale locale = const Locale('zh'),
    List<Object> overrides = const <Object>[],
    VoidCallback? onChanged,
  }) {
    return ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: _openKey,
                onPressed: () => WorldviewTab.showEdit(
                    ctx, launchExisting, onChanged ?? () {}),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(_openKey));
    await tester.pumpAndSettle();
  }

  testWidgets('the worldview manual form exposes a top Save action',
      (tester) async {
    setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await open(tester);

    expect(find.byKey(_saveActionKey), findsOneWidget);
    expect(_actionLabel(zh.saveAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creating a worldview persists through the top Save',
      (tester) async {
    setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await open(tester);

    await tester.enterText(_fieldByLabel(zh.nameLabel), '测试世界观甲');
    await tester.enterText(
        _fieldByLabel(zh.worldviewOverviewConcise), _descriptionA);
    await tester.pump();
    expect(_actionLabel(zh.saveAction), findsOneWidget,
        reason: 'an edited form stays on the Save state');

    await tester.tap(find.byKey(_saveActionKey));
    await waitFor(tester, _actionLabel(zh.savedAction));

    final rows = await loadWorldviews(tester);
    final saved = rows.firstWhere((row) => row['name'] == '测试世界观甲');
    expect(saved['description'], _descriptionA);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing an existing worldview persists and keeps its identity',
      (tester) async {
    setViewport(tester, width: 800, height: 900);
    // An existing simple-mode worldview, shaped the way the library hands it to
    // the editor.
    launchExisting = <String, dynamic>{
      'id': 'existing-worldview-1',
      'name': '已有世界观',
      'description': _descriptionA,
      'detail_json': jsonEncode(<String, dynamic>{
        'format_version': 2,
        'mode': 'simple',
        'modules': <String, dynamic>{
          'overview': <String, dynamic>{
            'summary': _descriptionA,
            'status': 'confirmed',
          },
        },
      }),
      'entries_json': '[]',
      'source': '',
    };
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await open(tester);

    // The existing name is preserved on open.
    expect(
      tester.widget<TextField>(_fieldByLabel(zh.nameLabel)).controller!.text,
      '已有世界观',
    );

    await tester.enterText(
        _fieldByLabel(zh.worldviewOverviewConcise), _descriptionB);
    await tester.pump();
    await tester.tap(find.byKey(_saveActionKey));
    await waitFor(tester, _actionLabel(zh.savedAction));

    final rows = await loadWorldviews(tester);
    final saved = rows.firstWhere((row) => row['id'] == 'existing-worldview-1');
    expect(saved['name'], '已有世界观');
    expect(saved['description'], _descriptionB);
    expect(
        rows.where((row) => row['id'] == 'existing-worldview-1'), hasLength(1),
        reason: 'editing must update in place, never create a second resource');
    expect(tester.takeException(), isNull);
  });

  testWidgets('top and bottom saves never create a duplicate resource',
      (tester) async {
    setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await open(tester);
    await tester.enterText(_fieldByLabel(zh.nameLabel), '唯一世界观');
    await tester.enterText(
        _fieldByLabel(zh.worldviewOverviewConcise), _descriptionA);
    await tester.pump();

    await tester.tap(find.byKey(_saveActionKey));
    await waitFor(tester, _actionLabel(zh.savedAction));
    // A second toolbar save with no further edits updates in place.
    await tester.tap(find.byKey(_saveActionKey));
    await tester.pumpAndSettle();
    // The footer button closes the page and must reuse the same resource.
    await tester.tap(find.widgetWithText(FilledButton, zh.saveAction));
    await tester.pumpAndSettle();

    final rows = await loadWorldviews(tester);
    expect(
      rows.where((row) => row['name'] == '唯一世界观'),
      hasLength(1),
      reason: 'repeated saves must not duplicate the resource',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the top Save shows a loading state and blocks a second write',
      (tester) async {
    setViewport(tester, width: 800, height: 900);
    final crud = _RecordingCrud();
    await tester.pumpWidget(app(overrides: [
      resourceCrudControllerProvider.overrideWith((ref) => crud),
    ]));
    await tester.pumpAndSettle();
    await open(tester);
    await tester.enterText(_fieldByLabel(zh.nameLabel), '加载中世界观');
    await tester.pump();

    final gate = Completer<void>();
    crud.gate = gate;
    await tester.tap(find.byKey(_saveActionKey));
    await tester.pump();

    expect(_actionLabel(zh.savingAction), findsOneWidget);
    final footer = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, zh.saveAction));
    expect(footer.onPressed, isNull,
        reason: 'the footer save shares the toolbar saving guard');

    await tester.tap(find.byKey(_saveActionKey));
    await tester.pump();
    expect(crud.saveCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed save is reported as failed, never as success',
      (tester) async {
    setViewport(tester, width: 800, height: 900);
    final crud = _RecordingCrud()..fail = true;
    await tester.pumpWidget(app(overrides: [
      resourceCrudControllerProvider.overrideWith((ref) => crud),
    ]));
    await tester.pumpAndSettle();
    await open(tester);
    await tester.enterText(_fieldByLabel(zh.nameLabel), '会失败的世界观');
    await tester.pump();

    await tester.tap(find.byKey(_saveActionKey));
    await tester.pumpAndSettle();

    expect(_actionLabel(zh.saveFailedAction), findsOneWidget);
    expect(_actionLabel(zh.savedAction), findsNothing);
    // The form stays open so the user can retry.
    expect(find.byKey(_saveActionKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the top Save fits a 320 px viewport', (tester) async {
    setViewport(tester, width: 320, height: 568);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await open(tester);

    expect(find.byKey(_saveActionKey), findsOneWidget);
    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.byType(IconButton)),
      findsOneWidget,
    );
    expect(find.byTooltip(zh.saveAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the top Save is localized in English', (tester) async {
    setViewport(tester, width: 800, height: 900);
    await tester.pumpWidget(app(locale: const Locale('en')));
    await tester.pumpAndSettle();
    await open(tester);

    expect(
      find.descendant(
          of: find.byKey(_saveActionKey), matching: find.text('Save')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
