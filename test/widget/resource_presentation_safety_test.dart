import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/streaming_generation_runtime_contracts.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_detail_page.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

final class _LeakyLibraryRuntime implements ResourceLibraryRuntime {
  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async => [
        const ResourceLibraryItem(
          id: 'res_cre_1234567890_secret',
          type: ResourceType.worldview,
          name: 'Worldview res_cre_1234567890_secret entityId: 99',
          summary:
              'Summary with file:///home/user/LT/db.sqlite and revision: 1',
          updatedAt: '2026-09-26',
          status: ResourceDisplayStatus.ready,
          isStudioAvailable: true,
          isConsumable: true,
          lifecycleState: ResourceLifecycleState.ready,
        ),
      ];

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async =>
      const ResourceOperationResult.success(message: '已移入回收站');

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      'item_1';
}

void main() {
  group('Resource Presentation Safety Tests', () {
    const forbiddenPatterns = [
      'res_cre_',
      'bp_',
      'gen_cre_',
      'att_',
      'task_',
      'entityId',
      'attributeId',
      'revision',
      'file:///',
      '/home/',
      'SELECT',
      'StackTrace',
      'Exception',
      'raw_json',
    ];

    testWidgets(
        'ResourceLibraryScreen never leaks technical tokens to the user',
        (tester) async {
      final runtime = _LeakyLibraryRuntime();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            resourceLibraryRuntimeProvider.overrideWithValue(runtime),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ResourceLibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final allTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .toList();

      for (final text in allTexts) {
        for (final token in forbiddenPatterns) {
          expect(
            text.contains(token),
            isFalse,
            reason:
                'Found forbidden token "$token" in rendered UI text: "$text"',
          );
        }
      }
    });

    testWidgets(
        'ResourceLibraryDetailPage never leaks technical tokens to the user',
        (tester) async {
      const leakyItem = ResourceLibraryItem(
        id: 'res_cre_1234567890_secret',
        type: ResourceType.character,
        name: 'Character res_cre_secret att_task_001',
        summary: 'Details with StackTrace: #0 main and SELECT * FROM resources',
        updatedAt: '2026-09-26',
        status: ResourceDisplayStatus.ready,
        isStudioAvailable: true,
        isConsumable: false,
        lifecycleState: ResourceLifecycleState.failed,
      );

      final mockTree = ResourceTree(
        resource: const Resource(
          id: ResourceId('res_cre_1234567890_secret'),
          type: ResourceType.character,
          name: 'Clean Name',
          summary: 'Clean Summary',
        ),
        sections: [
          const ResourceSection(
            id: SectionId('sec_1'),
            resourceId: ResourceId('res_cre_1234567890_secret'),
            title: 'Section res_cre_123 entityId: 10',
            summary: 'Summary with CAS and revision: 2',
            sortOrder: 0,
          ),
        ],
        parts: [
          const ResourcePart(
            id: PartId('part_1'),
            sectionId: SectionId('sec_1'),
            title: 'Part task_1 att_2',
            content: 'Clean prose without leaks',
            sortOrder: 0,
          ),
        ],
      );

      final mockSession = StreamingGenerationSession(
        sessionId: 'gen_cre_123456',
        resourceId: const ResourceId('res_cre_123456'),
        blueprintId: 'bp_123456',
        status: StreamingLifecycleStatus.failed,
        errorMessage: 'Exception: DB write error file:///home/db.sqlite',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ResourceLibraryDetailPage(
              item: leakyItem,
              onMoveToTrash: () async => 'deleted',
              tree: mockTree,
              session: mockSession,
              isConsumableOverride: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final allTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .toList();

      for (final text in allTexts) {
        for (final token in forbiddenPatterns) {
          expect(
            text.contains(token),
            isFalse,
            reason:
                'Found forbidden token "$token" in rendered detail text: "$text"',
          );
        }
      }
    });
  });
}
