import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/managers/quest_manager.dart';

void main() {
  group('QuestManager.handleAiTrigger', () {
    test('returns null when asynchronous quest persistence fails', () async {
      final manager = QuestManager(
        getQuests: (_) async => [],
        saveQuest: (_) async => throw StateError('storage unavailable'),
        updateQuest: (_, __) async {},
        deleteQuest: (_) async {},
        getGameState: () => null,
        setGameState: (_) {},
      );

      final result = await manager.handleAiTrigger(1, const {
        'title': '寻找失物',
      });

      expect(result, isNull);
      expect(manager.activeQuests, isEmpty);
    });
  });
}
