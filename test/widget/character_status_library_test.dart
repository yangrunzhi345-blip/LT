import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/character_status_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/character_status_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';

final _l10n = AppLocalizationsZh();

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

class _FakeStatusRuntime implements CharacterStatusLibraryRuntime {
  _FakeStatusRuntime(this.entries);
  final List<CharacterStatusLibraryEntry> entries;

  @override
  Future<List<CharacterStatusLibraryEntry>> load(
          ResourceLibraryMode mode) async =>
      entries;
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

CharacterStatusLibraryEntry _owner({
  required String id,
  required ResourceType type,
  required String name,
  required String at,
  required List<TrackedStateDefinition> definitions,
}) =>
    CharacterStatusLibraryEntry(
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

List<ResourceLibraryItem> _items() => [
      _item('alice', ResourceType.character, '艾莉丝', '2026-01-02'),
      _item('guard', ResourceType.npc, '北门守卫', '2026-01-01'),
      _item('world', ResourceType.worldview, '艾尔德兰', '2026-01-03'),
    ];

List<CharacterStatusLibraryEntry> _entries() => [
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
    ];

Widget _app({ResourceLibraryFilter? initialFilter}) => ProviderScope(
      overrides: [
        resourceLibraryRuntimeProvider
            .overrideWithValue(_FakeLibraryRuntime(_items())),
        characterStatusLibraryRuntimeProvider
            .overrideWithValue(_FakeStatusRuntime(_entries())),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: ResourceLibraryScreen(initialFilter: initialFilter),
      ),
    );

Widget _emptyApp() => ProviderScope(
      overrides: [
        resourceLibraryRuntimeProvider
            .overrideWithValue(_FakeLibraryRuntime(_items())),
        characterStatusLibraryRuntimeProvider
            .overrideWithValue(_FakeStatusRuntime(const [])),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const ResourceLibraryScreen(
          initialFilter: ResourceLibraryFilter.characterStatus,
        ),
      ),
    );

void main() {
  group('Character status view state', () {
    final state = CharacterStatusLibraryViewState(
      status: CharacterStatusLibraryStatus.ready,
      entries: [
        ..._entries(),
        // An owner with no definitions is never shown.
        _owner(
          id: 'bob',
          type: ResourceType.character,
          name: 'Bob',
          at: '2026-01-04',
          definitions: const [],
        ),
      ],
    );

    test('hides owners without definitions', () {
      expect(state.visibleEntries.map((e) => e.resourceId), ['alice', 'guard']);
      expect(state.visibleDefinitionCount, 2);
    });

    test('owner filter selects character or npc only', () {
      final npc = state.copyWith(ownerFilter: CharacterStatusOwnerFilter.npc);
      expect(npc.visibleEntries.map((e) => e.resourceId), ['guard']);
      final chars =
          state.copyWith(ownerFilter: CharacterStatusOwnerFilter.character);
      expect(chars.visibleEntries.map((e) => e.resourceId), ['alice']);
    });

    test('search matches owner, definition name and rule', () {
      expect(
        state.copyWith(query: '诅咒').visibleEntries.map((e) => e.resourceId),
        ['alice'],
      );
      expect(
        state.copyWith(query: '艾莉丝').visibleEntries.map((e) => e.resourceId),
        ['alice'],
      );
      expect(
        state.copyWith(query: '禁术').visibleEntries.map((e) => e.resourceId),
        ['alice'],
      );
      expect(state.copyWith(query: '无此角色').visibleEntries, isEmpty);
    });
  });

  group('Character status surface', () {
    testWidgets('is a first-class library filter', (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();

      expect(find.text(_l10n.resourceCharacterStatusTab), findsOneWidget);

      await tester
          .tap(find.byKey(const ValueKey('resource-filter-characterStatus')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('character-status-list')), findsOneWidget);
      expect(find.text('艾莉丝'), findsOneWidget);
      expect(find.text('诅咒侵蚀'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows character and NPC definitions, never a runtime value',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(
        _app(initialFilter: ResourceLibraryFilter.characterStatus),
      );
      await tester.pumpAndSettle();

      expect(find.text('诅咒侵蚀'), findsOneWidget);
      expect(find.text('警戒程度'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('character-status-owner-alice')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('character-status-owner-guard')),
        findsOneWidget,
      );
      // Definition-only surface: no runtime number is rendered.
      expect(find.textContaining('27'), findsNothing);
      expect(find.textContaining('/ 100'), findsNothing);
    });

    testWidgets('global empty state offers an owner-scoped add action',
        (tester) async {
      setViewport(tester, width: 1280, height: 900);
      await tester.pumpWidget(_emptyApp());
      await tester.pumpAndSettle();

      expect(
          find.text(_l10n.resourceCharacterStatusEmptyTitle), findsOneWidget);
      final add = find.text(_l10n.resourceCharacterStatusAdd);
      expect(add, findsOneWidget);

      await tester.tap(add);
      await tester.pumpAndSettle();

      // The add flow picks an owner; it never creates an owner-less status.
      expect(
        find.byKey(const ValueKey('character-status-pick-alice')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('does not overflow at 320 px with enlarged text',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        _app(initialFilter: ResourceLibraryFilter.characterStatus),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
