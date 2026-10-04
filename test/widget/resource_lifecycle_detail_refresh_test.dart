import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_detail_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/responsive_test_helper.dart';
import '../helpers/resource_studio_fakes.dart';

/// The Resource Detail must reflect the terminal validation state without the
/// user leaving and re-entering the page. These tests pin the lifecycle read
/// provider as the live source: a pending validating read shows the in-flight
/// presentation, and the persisted terminal state replaces it in place.
const _item = ResourceLibraryItem(
  id: 'res_life',
  type: ResourceType.worldview,
  name: '测试世界观',
  summary: '摘要',
  updatedAt: '2026-10-01 10:00',
  status: ResourceDisplayStatus.optimizing,
  isStudioAvailable: true,
  isConsumable: false,
  lifecycleState: ResourceLifecycleState.validating,
);

const _readyResult = ResourceLifecycleProjectionResult(
  resourceId: ResourceId('res_life'),
  state: ResourceLifecycleState.ready,
  assemblyReadiness: AssemblyReadinessRecord(
    resourceId: 'res_life',
    state: ReadinessState.ready,
    assemblyRevisionId: 'asm_1',
    assemblyContentHash: 'hash_1',
  ),
);

final _failedResult = ResourceLifecycleProjectionResult(
  resourceId: const ResourceId('res_life'),
  state: ResourceLifecycleState.failed,
  generationSession: StreamingGenerationSession(
    sessionId: 'gen_life',
    resourceId: const ResourceId('res_life'),
    blueprintId: 'bp_life',
    status: StreamingLifecycleStatus.completed,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  ),
  assemblyReadiness: const AssemblyReadinessRecord(
    resourceId: 'res_life',
    state: ReadinessState.failed,
    failureReason: 'test',
  ),
);

Widget _app({
  required Future<ResourceLifecycleProjectionResult> Function(String id)
      snapshot,
}) {
  final tree = buildStudioTestTree();
  final studio = FakeResourceStudioRuntime(
    tree: tree,
    session: buildStudioTestSession(tree),
  );
  addTearDown(studio.eventsController.close);
  return ProviderScope(
    overrides: [
      resourceStudioRuntimeProvider.overrideWithValue(studio),
      resourceLifecycleSnapshotProvider.overrideWith((ref, id) => snapshot(id)),
    ],
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.light(useMaterial3: true),
      home: Scaffold(
        body: ResourceLibraryDetailPage(
          item: _item,
          embedded: true,
          onMoveToTrash: () async => null,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('validating → passed updates the detail without leaving',
      (tester) async {
    setViewport(tester, width: 800, height: 1000);
    final completer = Completer<ResourceLifecycleProjectionResult>();

    await tester.pumpWidget(_app(snapshot: (_) => completer.future));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // While the read is pending, the item snapshot (validating) is shown.
    expect(find.text('质量校验中'), findsOneWidget);
    expect(find.text('正在校验质量...'), findsOneWidget);
    expect(find.text('不可用于冒险'), findsOneWidget);

    completer.complete(_readyResult);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('质量校验中'), findsNothing);
    expect(find.text('正在校验质量...'), findsNothing);
    expect(find.text('已准备完成'), findsOneWidget);
    expect(find.text('可用于冒险'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validating → failed updates the detail and offers re-validate',
      (tester) async {
    setViewport(tester, width: 800, height: 1000);
    final completer = Completer<ResourceLifecycleProjectionResult>();

    await tester.pumpWidget(_app(snapshot: (_) => completer.future));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('质量校验中'), findsOneWidget);

    completer.complete(_failedResult);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('质量校验中'), findsNothing);
    expect(find.text('正在校验质量...'), findsNothing);
    expect(find.text('生成失败'), findsOneWidget);
    expect(find.text('不可用于冒险'), findsOneWidget);
    expect(find.byKey(const Key('resource-revalidate-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
