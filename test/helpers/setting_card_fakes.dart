import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card_repository.dart';

/// In-memory card store used by the Phase 5b unit tests.
final class MemorySettingCardRepository implements SettingCardRepository {
  final Map<String, SettingCard> cards = <String, SettingCard>{};

  @override
  Future<SettingCard?> findById(String id) async => cards[id];

  @override
  Future<SettingCard?> findLegacyId(
    String legacyId, {
    SettingCardKind? kind,
  }) async {
    for (final card in cards.values) {
      if (card.legacyId != legacyId) continue;
      if (kind != null && card.kind != kind) continue;
      return card;
    }
    return null;
  }

  @override
  Future<bool> exists(String id) async => cards.containsKey(id);

  @override
  Future<bool> insertIfAbsent(SettingCard card) async {
    if (cards.containsKey(card.id)) return false;
    cards[card.id] = card;
    return true;
  }

  @override
  Future<List<SettingCard>> list({
    SettingCardKind? kind,
    bool includeDeleted = false,
  }) async {
    final result = cards.values
        .where((card) => kind == null || card.kind == kind)
        .where((card) => includeDeleted || !card.isDeleted)
        .toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<void> save(SettingCard card) async {
    cards[card.id] = card;
  }

  @override
  Future<void> softDelete(String id, {required String deletedAt}) async {
    final card = cards[id];
    if (card == null) return;
    cards[id] = card.copyWith(updatedAt: deletedAt, deletedAt: deletedAt);
  }
}

/// Minimal gateway: only the two single-shot generation calls Phase 5b uses.
final class FakeSettingCardGateway implements LlmGateway {
  FakeSettingCardGateway({
    this.configured = true,
    this.worldviewResponse = const <String, dynamic>{},
    this.characterResponse = const <String, dynamic>{},
    this.error,
  });

  bool configured;
  Map<String, dynamic> worldviewResponse;
  Map<String, dynamic> characterResponse;
  Object? error;

  int worldviewCalls = 0;
  int characterCalls = 0;
  final List<String> sources = <String>[];
  final List<String> worldviews = <String>[];
  final List<List<Map<String, String>>> associatedCharacterArgs =
      <List<Map<String, String>>>[];
  final List<int?> targetCharacterArgs = <int?>[];

  @override
  bool get isConfigured => configured;

  @override
  Future<Map<String, dynamic>> generateDetailedWorldview(
    String source, {
    int? targetTotalCharacters,
    void Function(WorldviewGenerationProgress progress)? onProgress,
    dynamic generationMode,
  }) async {
    worldviewCalls++;
    sources.add(source);
    targetCharacterArgs.add(targetTotalCharacters);
    onProgress?.call(const WorldviewGenerationProgress(
      completedQuestions: 1,
      totalQuestions: 2,
      partialText: '阶段一',
    ));
    final failure = error;
    if (failure != null) throw failure;
    return worldviewResponse;
  }

  @override
  Future<Map<String, dynamic>> generateDetailedResourceCharacter({
    required String source,
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    int? targetTotalCharacters,
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
    dynamic generationMode,
  }) async {
    characterCalls++;
    sources.add(source);
    worldviews.add(worldview);
    associatedCharacterArgs.add(associatedCharacters);
    targetCharacterArgs.add(targetTotalCharacters);
    onProgress?.call(1, 2, '生成中');
    final failure = error;
    if (failure != null) throw failure;
    return characterResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
