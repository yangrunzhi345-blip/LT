import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_generation_protocol.dart';
import 'package:lt_dialogue/domain/resources/section_control.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/pages/resource_studio_page.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../helpers/resource_capacity_fakes.dart';
import '../helpers/resource_studio_fakes.dart';
import '../helpers/responsive_test_helper.dart';
import '../helpers/section_control_fakes.dart';
import '../helpers/studio_scroll_helper.dart';

/// A 5-Part resource whose Part statuses the test controls independently.
ResourceTree buildRetryTree() {
  const resourceId = ResourceId('res_retry');
  const sectionId = SectionId('sec_retry');
  return ResourceTree(
    resource: const Resource(
      id: resourceId,
      type: ResourceType.worldview,
      name: '重试失败项测试资源',
    ),
    sections: const <ResourceSection>[
      ResourceSection(
        id: sectionId,
        resourceId: resourceId,
        title: '第一章',
        sortOrder: 0,
      ),
    ],
    parts: const <ResourcePart>[
      ResourcePart(
          id: PartId('part_1'),
          sectionId: sectionId,
          title: '已成功段落一',
          content: '正文一',
          sortOrder: 0),
      ResourcePart(
          id: PartId('part_2'),
          sectionId: sectionId,
          title: '失败段落二',
          content: '',
          sortOrder: 1),
      ResourcePart(
          id: PartId('part_3'),
          sectionId: sectionId,
          title: '已成功段落三',
          content: '正文三',
          sortOrder: 2),
      ResourcePart(
          id: PartId('part_4'),
          sectionId: sectionId,
          title: '失败段落四',
          content: '',
          sortOrder: 3),
      ResourcePart(
          id: PartId('part_5'),
          sectionId: sectionId,
          title: '失败段落五',
          content: '',
          sortOrder: 4),
    ],
  );
}

const _sessionId = 'gen_studio_test';

void main() {
  late FakeResourceStudioRuntime runtime;
  late ResourceTree tree;

  setUp(() {
    tree = buildRetryTree();
    runtime = FakeResourceStudioRuntime(
      tree: tree,
      session: buildStudioTestSession(tree),
    );
    runtime.partTaskStatuses = <String, PartTaskStatus>{
      'part_1': PartTaskStatus.completed,
      'part_2': PartTaskStatus.failed,
      'part_3': PartTaskStatus.completed,
      'part_4': PartTaskStatus.failed,
      'part_5': PartTaskStatus.failed,
    };
  });

  tearDown(() {
    runtime.dispose();
  });

  Widget app() {
    return ProviderScope(
      overrides: [
        resourceStudioRuntimeProvider.overrideWithValue(runtime),
        sectionControlRuntimeProvider.overrideWithValue(
          FakeSectionControlRuntime(entries: [
            SectionControlEntry(
              id: tree.sections.single.id,
              resourceId: tree.resource.id,
              title: '第一章',
              orderIndex: 0,
              content: '已有正文。',
              partCount: tree.parts.length,
              generationState: SectionGenerationState.failed,
              updatedAtToken: 'token-1',
            ),
          ]),
        ),
        resourceCapacityRuntimeProvider
            .overrideWithValue(FakeResourceCapacityRuntime()),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light(),
        home: const ResourceStudioPage(sessionId: _sessionId),
      ),
    );
  }

  Finder outlineRetry(String partId) =>
      find.byKey(ValueKey<String>('outline-retry-$partId'));

  // ── G. Failed Parts expose a retry; generated Parts do not. ─────────────

  testWidgets('only failed Parts expose the regenerate action', (tester) async {
    setViewport(tester, width: 1280, height: 900);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(outlineRetry('part_2'), findsOneWidget);
    expect(outlineRetry('part_4'), findsOneWidget);
    expect(outlineRetry('part_5'), findsOneWidget);
    // Generated Parts never offer the action.
    expect(outlineRetry('part_1'), findsNothing);
    expect(outlineRetry('part_3'), findsNothing);
    // The failed status label is visible.
    expect(find.text('生成失败'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping regenerate retries exactly that Part', (tester) async {
    setViewport(tester, width: 1280, height: 900);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(outlineRetry('part_4'));
    await tester.pumpAndSettle();

    expect(runtime.retryPartCalls, [(_sessionId, 'part_4')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a regenerating Part is disabled and shows a loading state',
      (tester) async {
    setViewport(tester, width: 1280, height: 900);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final gate = Completer<void>();
    runtime.retryPartGate = gate;

    await tester.tap(outlineRetry('part_2'));
    await tester.pump();

    // Outline row shows the retry as in flight...
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('resource_studio_outline')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    // ...the card reports it, and the row no longer offers a tappable retry, so
    // a second request for the same Part cannot be issued.
    expect(find.text('重新生成中…'), findsWidgets);
    expect(outlineRetry('part_2'), findsNothing);
    expect(runtime.retryPartCalls, hasLength(1));

    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // ── E. Batch regenerate targets exactly the failed Parts. ───────────────

  testWidgets('regenerate failed parts only retries the failed ones',
      (tester) async {
    setViewport(tester, width: 1280, height: 900);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await openStudioInspector(tester);

    final batch = find.byKey(const Key('studio-retry-failed-parts'));
    expect(batch, findsOneWidget);
    await tester.tap(batch);
    await tester.pumpAndSettle();

    expect(
      runtime.retryPartCalls,
      [(_sessionId, 'part_2'), (_sessionId, 'part_4'), (_sessionId, 'part_5')],
      reason: 'only the failed Parts, in tree order',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the batch action is hidden when no Part has failed',
      (tester) async {
    runtime.partTaskStatuses = <String, PartTaskStatus>{
      for (final part in tree.parts) part.id.value: PartTaskStatus.completed,
    };
    setViewport(tester, width: 1280, height: 900);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await openStudioInspector(tester);

    expect(find.byKey(const Key('studio-retry-failed-parts')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // ── H. Responsive: no overflow at the minimum supported width. ──────────

  for (final size in const <Size>[
    Size(320, 568),
    Size(360, 640),
    Size(390, 844),
    Size(768, 1024),
  ]) {
    testWidgets('failed-part retry has no overflow at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      // The outline is a bottom sheet on a phone; open it so the per-Part
      // retry action is on screen at every width.
      if (size.width < 600) {
        await tester.tap(
          find.byKey(const ValueKey('resource_studio_outline_toggle')),
        );
        await tester.pumpAndSettle();
      }
      expect(outlineRetry('part_2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
