import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/models/scene_batch_candidate.dart';
import 'package:lt_dialogue/screens/resource_library/resource_import_review_page.dart';
import 'package:lt_dialogue/screens/resource_library/scene_batch_import_page.dart';

import '../helpers/responsive_test_helper.dart';

void main() {
  group('Resource import review navigation', () {
    testWidgets('should review long generated content at 320px',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      tester.view.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(
        tester.view.platformDispatcher.clearTextScaleFactorTestValue,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ResourceImportReviewPage(
            title: '确认导入世界观',
            child: Text('很长的生成预览内容。' * 100),
          ),
        ),
      );

      expect(find.text('返回修改'), findsOneWidget);
      expect(find.text('确认保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('should return selected candidates without a dialog',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      List<SceneBatchCandidate>? result;
      const candidates = [
        SceneBatchCandidate(
          sourceId: 'first',
          displayName: '一位名字非常长的候选角色用于验证窄屏换行',
        ),
        SceneBatchCandidate(sourceId: 'second', displayName: '第二位角色'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result =
                    await Navigator.of(context).push<List<SceneBatchCandidate>>(
                  MaterialPageRoute(
                    builder: (_) => const SceneBatchCandidateSelectPage(
                      candidates: candidates,
                    ),
                  ),
                );
              },
              child: const Text('打开选择'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开选择'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('第二位角色'));
      await tester.pump();
      await tester.tap(find.text('导入 1 个角色'));
      await tester.pumpAndSettle();

      expect(result, [candidates.first]);
      expect(tester.takeException(), isNull);
    });
  });
}
