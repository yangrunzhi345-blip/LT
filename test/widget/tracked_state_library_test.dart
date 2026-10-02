import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/resource_library/edit_drafts.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/tracked_state_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/tracked_state_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_tracked_state_edit_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';

import '../helpers/responsive_test_helper.dart';

final _l10n = AppLocalizationsZh();

class _FakeRepo implements ILibraryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeLibraryRuntime implements ResourceLibraryRuntime {
  _FakeLibraryRuntime(this.items);
  final List<ResourceLibraryItem> items;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async =>
      items;

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async =>
      throw UnimplementedError();

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      throw UnimplementedError();
}

class _FakeTrackedStateRuntime implements TrackedStateLibraryRuntime {
  _FakeTrackedStateRuntime(this.entries, {this.rows = const {}});
  final List<TrackedStateLibraryEntry> entries;
  final Map<String, Map<String, dynamic>> rows;

  @override
  Future<List<TrackedStateLibraryEntry>> load(ResourceLibraryMode mode) async =>
      entries;

  @override
  Future<Map<String, dynamic>?> loadOwnerRow({
    required ResourceType type,
    required String resourceId,
    required ResourceLibraryMode mode,
  }) async =>
      rows[resourceId];
}

class _RecordingCrud extends ResourceCrudController {
  _RecordingCrud() : super(repository: _FakeRepo());

  CharacterCardEditDraft? savedCharacter;
  NpcEditDraft? savedNpc;
  WorldviewEditDraft? savedWorldview;

  @override
  Future<ResourceOperationResult> saveCharacterCardDraft(
    CharacterCardEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    savedCharacter = draft;
    return const ResourceOperationResult.success();
  }

  @override
  Future<ResourceOperationResult> saveNpcDraft(
    NpcEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    savedNpc = draft;
    return const ResourceOperationResult.success();
  }

  @override
  Future<ResourceOperationResult> saveWorldviewDraft(
    WorldviewEditDraft draft, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) async {
    savedWorldview = draft;
    return const ResourceOperationResult.success();
  }
}

ResourceLibraryItem _item(
        String id, ResourceType type, String name, String at) =>
    ResourceLibraryItem(
      id: id,
      type: type,
      name: name,
      summary: '',
      updatedAt: at,
      status: ResourceDisplayStatus.ready,
      isStudioAvailable: true,
    );

TrackedStateLibraryEntry _owner({
  required String id,
  required ResourceType type,
  required String name,
  required String at,
  required List<TrackedStateDefinition> definitions,
}) =>
    TrackedStateLibraryEntry(
      resourceId: id,
      ownerType: type,
      ownerName: name,
      updatedAt: at,
      definitions: definitions,
    );

const _curse = TrackedStateDefinition(
  id: 'curse',
  name: '诅咒侵蚀',
  valueKind: RuntimeStateValueKind.integer,
  description: '接触深渊力量或使用禁术时增加',
  importance: CustomAttributeImportance.critical,
  minimum: 0,
  maximum: 100,
);

const _alertness = TrackedStateDefinition(
  id: 'alertness',
  name: '警戒程度',
  valueKind: RuntimeStateValueKind.integer,
  minimum: 0,
  maximum: 100,
);

const _warTension = TrackedStateDefinition(
  id: 'war_tension',
  name: '战争紧张度',
  valueKind: RuntimeStateValueKind.integer,
  description: '国家间正式发生军事冲突时增加',
  importance: CustomAttributeImportance.critical,
  minimum: 0,
  maximum: 100,
);

List<ResourceLibraryItem> _items() => [
      _item('alice', ResourceType.character, '艾莉丝', '2026-01-02'),
      _item('guard', ResourceType.npc, '北门守卫', '2026-01-01'),
      _item('world', ResourceType.worldview, '艾尔德兰', '2026-01-03'),
    ];

List<TrackedStateLibraryEntry> _entries() => [
      _owner(
        id: 'alice',
        type: ResourceType.character,
        name: '艾莉丝',
        at: '2026-01-02',
        definitions: const [_curse],
      ),
      _owner(
        id: 'guard',
        type: ResourceType.npc,
        name: '北门守卫',
        at: '2026-01-01',
        definitions: const [_alertness],
      ),
      _owner(
        id: 'world',
        type: ResourceType.worldview,
        name: '艾尔德兰',
        at: '2026-01-03',
        definitions: const [_warTension],
      ),
    ];

Widget _app({
  ResourceLibraryFilter? initialFilter,
  List<TrackedStateLibraryEntry>? entries,
  Map<String, Map<String, dynamic>> rows = const {},
}) =>
    ProviderScope(
      overrides: [
        resourceLibraryRuntimeProvider
            .overrideWithValue(_FakeLibraryRuntime(_items())),
        trackedStateLibraryRuntimeProvider.overrideWithValue(
            _FakeTrackedStateRuntime(entries ?? _entries(), rows: rows)),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: ResourceLibraryScreen(initialFilter: initialFilter),
      ),
    );

/// Pushes the focused editor onto a placeholder home so saving (which pops) is
/// a safe navigation instead of popping the root route.
Widget _editorHost({
  required ResourceType type,
  required String resourceId,
  required Map<String, dynamic> row,
  required _RecordingCrud crud,
}) =>
    ProviderScope(
      overrides: [
        trackedStateLibraryRuntimeProvider.overrideWithValue(
            _FakeTrackedStateRuntime(const [], rows: {resourceId: row})),
        resourceCrudControllerProvider.overrideWith((ref) => crud),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => ResourceTrackedStateEditPage(
                      ownerType: type,
                      resourceId: resourceId,
                    ),
                  ),
                ),
                child: const Text('open-editor'),
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.text('open-editor'));
  await tester.pumpAndSettle();
}

/// The name field of the newly added definition card (keyed `new-<index>`).
Finder _newDefinitionNameField(int existingCount) => find
    .descendant(
      of: find.byKey(ValueKey('new-$existingCount')),
      matching: find.byType(TextField),
    )
    .first;

void main() {
  group('Tracked state view state', () {
    final state = TrackedStateLibraryViewState(
      status: TrackedStateLibraryStatus.ready,
      entries: [
        ..._entries(),
        _owner(
          id: 'bob',
          type: ResourceType.character,
          name: 'Bob',
          at: '2026-01-04',
          definitions: const [],
        ),
      ],
    );

    test(
        'covers character, npc and worldview; hides owners without definitions',
        () {
      expect(
        state.visibleEntries.map((e) => e.ownerType).toSet(),
        {ResourceType.character, ResourceType.npc, ResourceType.worldview},
      );
      expect(state.visibleEntries.map((e) => e.resourceId),
          isNot(contains('bob')));
      expect(state.visibleDefinitionCount, 3);
    });

    test('owner filter selects worldview independently', () {
      final worldview =
          state.copyWith(ownerFilter: TrackedStateOwnerFilter.worldview);
      expect(worldview.visibleEntries.map((e) => e.resourceId), ['world']);
    });

    test('search matches owner, definition name and rule (incl. worldview)',
        () {
      expect(
        state.copyWith(query: '战争').visibleEntries.map((e) => e.resourceId),
        ['world'],
      );
      expect(
        state.copyWith(query: '艾尔德兰').visibleEntries.map((e) => e.resourceId),
        ['world'],
      );
      expect(
        state.copyWith(query: '警戒').visibleEntries.map((e) => e.resourceId),
        ['guard'],
      );
      expect(state.copyWith(query: '无此资源').visibleEntries, isEmpty);
    });
  });

  group('Tracked state surface', () {
    testWidgets('is a first-class library filter named 检测项目', (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      // 检测项目 appears as the filter tab and, once active, as the owner
      // filter's label.
      expect(find.text(_l10n.resourceTrackedStateTab), findsWidgets);
      expect(
        find.byKey(const ValueKey('resource-filter-trackedState')),
        findsOneWidget,
      );

      await tester
          .tap(find.byKey(const ValueKey('resource-filter-trackedState')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tracked-state-list')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'shows character, NPC and worldview definitions, no runtime value',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(
        _app(initialFilter: ResourceLibraryFilter.trackedState),
      );
      await tester.pumpAndSettle();

      expect(find.text('诅咒侵蚀'), findsOneWidget);
      expect(find.text('警戒程度'), findsOneWidget);
      expect(find.text('战争紧张度'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('tracked-state-owner-world')),
        findsOneWidget,
      );
      expect(find.textContaining('/ 100'), findsNothing);
      expect(find.textContaining('72'), findsNothing);
    });

    testWidgets(
        'global empty state offers an owner picker with all three types',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(_app(
        initialFilter: ResourceLibraryFilter.trackedState,
        entries: const [],
      ));
      await tester.pumpAndSettle();

      expect(find.text(_l10n.resourceTrackedStateEmptyTitle), findsOneWidget);
      final add = find.text(_l10n.resourceTrackedStateAdd);
      expect(add, findsOneWidget);

      await tester.tap(add);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tracked-state-pick-alice')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('tracked-state-pick-guard')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('tracked-state-pick-world')),
          findsOneWidget);
    });

    testWidgets('does not overflow at 320 px with enlarged text',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _app(initialFilter: ResourceLibraryFilter.trackedState),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('Focused tracked-state editor', () {
    testWidgets('opens from the surface for an NPC (no longer read-only)',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      final guardRow = {
        'id': 'guard',
        'name': '北门守卫',
        'json_data': jsonEncode({'name': '北门守卫'}),
      };
      await tester.pumpWidget(_app(
        initialFilter: ResourceLibraryFilter.trackedState,
        rows: {'guard': guardRow},
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tracked-state-edit-guard')));
      await tester.pumpAndSettle();

      expect(find.byType(ResourceTrackedStateEditPage), findsOneWidget);
      expect(find.text(_l10n.trackedStateAddAction), findsOneWidget);
      expect(find.byKey(const Key('tracked-state-edit-save')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('saves a character definition and preserves other fields',
        (tester) async {
      setViewport(tester, width: 1000, height: 900);
      final crud = _RecordingCrud();
      final row = {
        'id': 'alice',
        'name': '艾莉丝',
        'json_data': jsonEncode({
          'name': '艾莉丝',
          'profession': '游侠',
          'unknown_field': 'keep-me',
          'tracked_state_definitions': [_curse.toJson()],
        }),
      };
      await tester.pumpWidget(_editorHost(
        type: ResourceType.character,
        resourceId: 'alice',
        row: row,
        crud: crud,
      ));
      await _openEditor(tester);

      await tester.tap(find.text(_l10n.trackedStateAddAction));
      await tester.pumpAndSettle();
      await tester.enterText(_newDefinitionNameField(1), '身份暴露风险');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracked-state-edit-save')));
      await tester.pumpAndSettle();

      final saved = crud.savedCharacter;
      expect(saved, isNotNull);
      expect(saved!.name, '艾莉丝');
      expect(saved.profession, '游侠');
      expect(saved.trackedStateDefinitions.length, 2);
      expect(saved.trackedStateDefinitions.last.name, '身份暴露风险');
      final stored = jsonDecode(saved.toStoredJson()) as Map<String, dynamic>;
      expect(stored['unknown_field'], 'keep-me');
    });

    testWidgets('saves an NPC definition and preserves other JSON fields',
        (tester) async {
      setViewport(tester, width: 1000, height: 900);
      final crud = _RecordingCrud();
      final row = {
        'id': 'guard',
        'name': '北门守卫',
        'json_data': jsonEncode({
          'name': '北门守卫',
          'gender': '男',
          'profession': '守卫',
          'appearance': '高大',
          'mystery_key': 'secret',
          'tracked_state_definitions': <Object>[],
        }),
      };
      await tester.pumpWidget(_editorHost(
        type: ResourceType.npc,
        resourceId: 'guard',
        row: row,
        crud: crud,
      ));
      await _openEditor(tester);

      await tester.tap(find.text(_l10n.trackedStateAddAction));
      await tester.pumpAndSettle();
      await tester.enterText(_newDefinitionNameField(0), '警戒程度');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracked-state-edit-save')));
      await tester.pumpAndSettle();

      final saved = crud.savedNpc;
      expect(saved, isNotNull);
      final stored = jsonDecode(saved!.toStoredJson()) as Map<String, dynamic>;
      expect(stored['gender'], '男');
      expect(stored['profession'], '守卫');
      expect(stored['appearance'], '高大');
      expect(stored['mystery_key'], 'secret');
      final defs = stored['tracked_state_definitions'] as List<dynamic>;
      expect(defs, hasLength(1));
      expect((defs.single as Map)['name'], '警戒程度');
    });

    testWidgets('saves a worldview definition and preserves detail metadata',
        (tester) async {
      setViewport(tester, width: 1000, height: 900);
      final crud = _RecordingCrud();
      final row = {
        'id': 'world',
        'name': '艾尔德兰',
        'description': '一片动荡的大陆',
        'entries_json': '[{"a":1}]',
        'detail_json': jsonEncode({
          'format_version': 1,
          'mode': 'detailed',
          'modules': {
            'overview': {'summary': '概述', 'status': 'confirmed'},
            'world_rules': {'content': '魔法有限', 'status': 'confirmed'},
          },
          'tracked_state_definitions': [_warTension.toJson()],
        }),
      };
      await tester.pumpWidget(_editorHost(
        type: ResourceType.worldview,
        resourceId: 'world',
        row: row,
        crud: crud,
      ));
      await _openEditor(tester);

      await tester.tap(find.text(_l10n.trackedStateAddAction));
      await tester.pumpAndSettle();
      await tester.enterText(_newDefinitionNameField(1), '魔力潮汐');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('tracked-state-edit-save')));
      await tester.pumpAndSettle();

      final saved = crud.savedWorldview;
      expect(saved, isNotNull);
      expect(saved!.description, '一片动荡的大陆');
      expect(saved.entriesJson, '[{"a":1}]');
      final details = saved.toDetails();
      expect(details.modules.keys, contains('world_rules'));
      expect(details.trackedStateDefinitions.map((d) => d.name),
          containsAll(<String>['战争紧张度', '魔力潮汐']));
    });
  });
}
