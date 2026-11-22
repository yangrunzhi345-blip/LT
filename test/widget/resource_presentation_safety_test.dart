import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
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
  });
}
