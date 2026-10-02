import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/resources/resource_read_facade.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_detail_page.dart';
import 'package:lt_dialogue/features/resource_studio/application/use_cases/resource_studio_runtime.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';

class _FakeLibraryRepo implements ILibraryRepository {
  _FakeLibraryRepo(this.row);

  final Map<String, Object?>? row;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<ResourceReadResult> readResourcePreferringTree({
    required ResourceType type,
    required String legacyId,
  }) async =>
      ResourceReadResult(
        source: ResourceReadSource.legacyFallback,
        legacyId: legacyId,
        legacyRow: row,
      );
}

class _FakeStudio implements ResourceStudioRuntime {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;

  @override
  Future<ResourceTree?> readTree(ResourceId resourceId) async => null;
}

ResourceLibraryItem _item(ResourceType type, String name) =>
    ResourceLibraryItem(
      id: 'res-1',
      type: type,
      name: name,
      summary: '',
      updatedAt: '',
      status: ResourceDisplayStatus.ready,
      isStudioAvailable: false,
    );

Future<void> _pump(
  WidgetTester tester, {
  required ResourceLibraryItem item,
  required Map<String, Object?>? row,
}) async {
  final container = ProviderContainer(overrides: [
    libraryRepoProvider.overrideWithValue(_FakeLibraryRepo(row)),
    resourceStudioRuntimeProvider.overrideWithValue(_FakeStudio()),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: ResourceLibraryDetailPage(
        item: item,
        onMoveToTrash: () async => '',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l10n = AppLocalizationsZh();

  testWidgets('character detail lists monitored definitions without values',
      (tester) async {
    await _pump(
      tester,
      item: _item(ResourceType.character, '艾莉丝'),
      row: {
        'id': 'c1',
        'name': '艾莉丝',
        'json_data': '{"name":"艾莉丝","tracked_state_definitions":['
            '{"id":"curse","name":"诅咒侵蚀","value_kind":"integer",'
            '"minimum":0,"maximum":100,"importance":"critical",'
            '"description":"接触污染时增加，净化时降低"},'
            '{"id":"exposure","name":"身份暴露风险","value_kind":"integer",'
            '"minimum":0,"maximum":100,"importance":"important"}]}',
      },
    );

    expect(find.text(l10n.trackedStateMonitorLabel), findsAtLeastNWidgets(1));
    expect(find.text('诅咒侵蚀'), findsOneWidget);
    expect(find.text('身份暴露风险'), findsOneWidget);
    // Definitions only — never an adventure runtime current value.
    expect(find.textContaining('27'), findsNothing);
    expect(find.textContaining('37 / 100'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worldview detail lists monitored definitions', (tester) async {
    await _pump(
      tester,
      item: _item(ResourceType.worldview, '艾尔德兰'),
      row: {
        'id': 'w1',
        'name': '艾尔德兰',
        'detail_json': '{"format_version":2,"mode":"simple","modules":{},'
            '"tracked_state_definitions":['
            '{"id":"war_tension","name":"战争紧张度","value_kind":"integer",'
            '"minimum":0,"maximum":100}]}',
      },
    );

    expect(find.text('战争紧张度'), findsOneWidget);
    expect(find.textContaining('65'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resource with no definitions shows a clear empty line',
      (tester) async {
    await _pump(
      tester,
      item: _item(ResourceType.character, '普通角色'),
      row: {
        'id': 'c2',
        'name': '普通角色',
        'json_data': '{"name":"普通角色"}',
      },
    );

    expect(find.text(l10n.trackedStateResourceEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
