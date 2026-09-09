import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/screens/resource_library/resource_card_ai_import_page.dart';

void main() {
  testWidgets('detailed character import should fit supported mobile widths',
      (tester) async {
    addTearDown(tester.view.reset);
    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(390, 844),
      Size(412, 915),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.4),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: ResourceCardAiImportPage(
                kind: ResourceCardImportKind.character,
                worldviews: const [
                  {'id': 'white-harbor', 'name': '白港炼金世界'},
                ],
                characterCards: const [],
                detailInstruction: '',
                aiDepth: AiGenerationDepth.detailed,
                mode: ResourceLibraryMode.adventure,
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull, reason: 'viewport: $size');
      expect(find.textContaining('目标有效内容'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('AI 解析'), findsOneWidget);
    }
  });
}
