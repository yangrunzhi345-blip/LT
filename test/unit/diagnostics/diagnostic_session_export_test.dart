import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/diagnostics/diagnostic_session_export.dart';
import 'package:lt_dialogue/models/diagnostics/diagnostic_turn_export.dart';

void main() {
  group('DiagnosticSessionExport Models', () {
    test('serializes and deserializes conforming to schema v1', () {
      final export = DiagnosticSessionExport(
        exportedAt: '2026-09-15T15:00:00+08:00',
        application: const DiagnosticApplicationInfo(
          name: 'LT Dialogue',
          version: '1.1.11+14',
          platform: 'linux',
        ),
        scope: const DiagnosticScope(
          adventureId: 12,
          adventureTitle: '王城调查',
          branchId: 0,
          branchName: 'main',
          headRevision: 83,
          turnRange: DiagnosticTurnRange(
            mode: 'recent',
            requested: 30,
            actual: 1,
          ),
        ),
        runtimeSnapshot: const DiagnosticRuntimeSnapshot(
          headRevision: 83,
          headCommitId: 'runtime-req_101',
          sceneState: DiagnosticSceneStateSnapshot(
            location: '皇家图书馆',
            time: '黄昏',
            presentCharacterIds: ['protagonist', 'elena'],
            activeGoals: [
              {'id': 'g1', 'description': '寻找古籍', 'status': 'active'}
            ],
          ),
          entities: [
            DiagnosticEntitySnapshot(
              entityType: 'character',
              entityId: 'elena',
              lifecycleStatus: 'active',
              lastCommitId: 'runtime-req_101',
              overlay: {'affinity': 65},
            ),
          ],
        ),
        turns: [
          const DiagnosticTurnExport(
            turnIndex: 1,
            requestId: 'req_101',
            createdAt: '2026-09-15T14:50:00+08:00',
            user: DiagnosticMessage(
              messageId: 'u1',
              content: '向前探索',
              timestamp: '2026-09-15T14:50:00+08:00',
              isUser: true,
            ),
            assistant: DiagnosticMessage(
              messageId: 'a1',
              content: '你走进了昏暗的走廊……',
              timestamp: '2026-09-15T14:50:05+08:00',
              isUser: false,
              options: ['拔出武器', '点亮火把'],
            ),
            runtime: DiagnosticTurnRuntime(
              committed: true,
              commitId: 'runtime-req_101',
              revisionBefore: 82,
              revisionAfter: 83,
              summary: '艾莲娜好感提升',
              changes: [
                DiagnosticRuntimeChange(
                  entityType: 'character',
                  entityId: 'elena',
                  changeKind: 'primary',
                  operation: 'increment',
                  path: 'affinity',
                  before: 60,
                  after: 65,
                  reason: '并肩作战',
                ),
              ],
            ),
            diagnostics: {
              'budget_tokens': 1024,
              'length_final_verdict': 'within_range',
            },
          ),
        ],
        exportWarnings: [],
      );

      final jsonMap = export.toJson();

      // Rule 4: Verify root schema fields and absence of $schema
      expect(jsonMap['schema'], equals('lt.diagnostic_session'));
      expect(jsonMap['schema_version'], equals(1));
      expect(jsonMap.containsKey(r'$schema'), isFalse);

      // Rule 5: Verify turn_index is present and turn is absent
      final turnMap = (jsonMap['turns'] as List).first as Map<String, dynamic>;
      expect(turnMap['turn_index'], equals(1));
      expect(turnMap.containsKey('turn'), isFalse);

      // Rule 3: Verify changes do not have source field
      final changes = (turnMap['runtime'] as Map)['changes'] as List;
      final change = changes.first as Map<String, dynamic>;
      expect(change.containsKey('source'), isFalse);
      expect(change['path'], equals('affinity'));
      expect(change['before'], equals(60));
      expect(change['after'], equals(65));

      // Test round-trip serialization / deserialization
      final pretty = export.toPrettyJson();
      final decoded = jsonDecode(pretty) as Map<String, dynamic>;
      final reExport = DiagnosticSessionExport.fromJson(decoded);

      expect(reExport.schema, equals(export.schema));
      expect(reExport.schemaVersion, equals(export.schemaVersion));
      expect(reExport.scope.adventureTitle, equals('王城调查'));
      expect(reExport.turns.first.turnIndex, equals(1));
      expect(reExport.turns.first.assistant.options, equals(['拔出武器', '点亮火把']));
      expect(reExport.turns.first.runtime.changes.first.after, equals(65));
    });

    test('handles unlinked user message gracefully with null user', () {
      const turnWithoutUser = DiagnosticTurnExport(
        turnIndex: 1,
        requestId: 'req_orphan',
        createdAt: '2026-09-15T14:00:00+08:00',
        user: null,
        assistant: DiagnosticMessage(
          messageId: 'a_orphan',
          content: '序幕陈述',
          timestamp: '2026-09-15T14:00:01+08:00',
          isUser: false,
        ),
        runtime: DiagnosticTurnRuntime(committed: false),
      );

      final map = turnWithoutUser.toJson();
      expect(map['user'], isNull);

      final restored = DiagnosticTurnExport.fromJson(map);
      expect(restored.user, isNull);
      expect(restored.assistant.content, equals('序幕陈述'));
    });
  });
}
