import 'package:mocktail/mocktail.dart';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/application/resource_library/import_models.dart';
import 'package:lt_dialogue/models/resource_provenance.dart';
import 'package:lt_dialogue/models/scene_batch_candidate.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';

/// 记录 [ILibraryRepository.saveCardBatch] 调用的测试 spy。
class SceneBatchSaveSpy {
  final List<List<LibraryCardBatchItem>> calls = [];

  bool get wasCalled => calls.isNotEmpty;
  List<LibraryCardBatchItem> get last => calls.last;
}

SceneBatchImportRequest buildSceneBatchRequest({
  String kind = 'character',
  List<Map<String, dynamic>> related = const [],
  int minimumTotalLength = 1000,
  int maximumTotalLength = 5000,
}) =>
    SceneBatchImportRequest(
      source: '林月与玄霜门的故事。',
      kind: kind,
      detailInstruction: '详细模式',
      aiDepth: AiGenerationDepth.detailed,
      minimumTotalLength: minimumTotalLength,
      maximumTotalLength: maximumTotalLength,
      relatedCharacters: related,
    );

/// 按候选 sourceId 返回固定生成结果；未配置的候选抛出异常。
void stubSceneBatchCharacterGeneration(
  LlmGateway gateway,
  Map<String, Map<String, dynamic>> bySourceId,
) {
  when(
    () => gateway.generateSceneBatchCharacter(
      source: any(named: 'source'),
      label: any(named: 'label'),
      worldview: any(named: 'worldview'),
      relatedCharacters: any(named: 'relatedCharacters'),
      candidate: any(named: 'candidate'),
      minimumTotalLength: any(named: 'minimumTotalLength'),
      maximumTotalLength: any(named: 'maximumTotalLength'),
      detailInstruction: any(named: 'detailInstruction'),
    ),
  ).thenAnswer((invocation) async {
    final candidate =
        invocation.namedArguments[#candidate] as SceneBatchCandidate;
    final item = bySourceId[candidate.sourceId];
    if (item == null) {
      throw StateError('no stubbed generation for ${candidate.sourceId}');
    }
    return Map<String, dynamic>.from(item);
  });
}

/// 让连续多次调用可返回不同的生成结果（用于单候选重试/失败隔离测试）。
void stubSceneBatchCharacterAttempts(
  LlmGateway gateway,
  Map<String, List<Map<String, dynamic> Function()>> bySourceId,
) {
  final counters = <String, int>{};
  when(
    () => gateway.generateSceneBatchCharacter(
      source: any(named: 'source'),
      label: any(named: 'label'),
      worldview: any(named: 'worldview'),
      relatedCharacters: any(named: 'relatedCharacters'),
      candidate: any(named: 'candidate'),
      minimumTotalLength: any(named: 'minimumTotalLength'),
      maximumTotalLength: any(named: 'maximumTotalLength'),
      detailInstruction: any(named: 'detailInstruction'),
    ),
  ).thenAnswer((invocation) async {
    final candidate =
        invocation.namedArguments[#candidate] as SceneBatchCandidate;
    final attempts = bySourceId[candidate.sourceId];
    if (attempts == null || attempts.isEmpty) {
      throw StateError('no stubbed attempts for ${candidate.sourceId}');
    }
    final index = counters.update(
      candidate.sourceId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final attempt = attempts[(index - 1).clamp(0, attempts.length - 1)];
    return attempt();
  });
}

SceneBatchSaveSpy stubSceneBatchSave(ILibraryRepository repository) {
  final spy = SceneBatchSaveSpy();
  when(
    () => repository.saveCardBatch(
      type: any(named: 'type'),
      items: any(named: 'items'),
      mode: any(named: 'mode'),
    ),
  ).thenAnswer((invocation) async {
    final items =
        invocation.namedArguments[#items] as List<LibraryCardBatchItem>;
    spy.calls.add(items);
    return items.length;
  });
  return spy;
}

void verifyNoSceneBatchSave(ILibraryRepository repository) {
  verifyNever(
    () => repository.saveCardBatch(
      type: any(named: 'type'),
      items: any(named: 'items'),
      mode: any(named: 'mode'),
    ),
  );
}
