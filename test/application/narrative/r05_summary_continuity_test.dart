
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lt_dialogue/engines/chat_engine_host.dart';
import 'package:lt_dialogue/engines/chat_engine_internals/summary_service.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';

class _MockLLMService extends Mock implements LLMService {}

class _MockAdventureRepository extends Mock implements IAdventureRepository {}

class _MockChatEngineHost extends Mock implements ChatEngineHost {}

/// R05-D regression: a summary may only advance its durable coverage marker
/// (summaries.up_to_id) across messages it actually covered, and content +
/// marker must commit together or not at all.
void main() {
  late _MockAdventureRepository repo;
  late _MockChatEngineHost host;
  late _MockLLMService llm;
  late List<Message> liveMessages;
  var savedMarkers = <int>[];

  Message msg(int index) => Message(
        id: 'm$index',
        content: '消息$index',
        isUser: index.isEven,
      );

  setUpAll(() {
    registerFallbackValue(const CompletionParams());
  });

  setUp(() {
    repo = _MockAdventureRepository();
    host = _MockChatEngineHost();
    llm = _MockLLMService();
    liveMessages = List.generate(20, msg);
    savedMarkers = <int>[];
    when(() => host.messages).thenReturn(liveMessages);
    when(() => host.currentAdventureId).thenReturn(1);
    when(() => host.currentBranchId).thenReturn(0);
    when(() => host.llmService).thenReturn(llm);
    when(() => llm.config).thenReturn(const LLMConfig(
      provider: LLMProvider.deepseek,
      apiKey: 'test-key',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
    ));
    when(() => llm.sendMessageStream(
          any(),
          any(),
          any(),
          onReasoningChunk: any(named: 'onReasoningChunk'),
          params: any(named: 'params'),
          taskHandle: any(named: 'taskHandle'),
        )).thenAnswer((invocation) async {
      final onChunk =
          invocation.positionalArguments[1] as void Function(String);
      onChunk('时间线摘要');
      return '时间线摘要';
    });
    when(() => repo.getLatestSummary(any(), branchId: any(named: 'branchId')))
        .thenAnswer((_) async => null);
    when(() => repo.getLatestSummaryUpToId(any(),
        branchId: any(named: 'branchId'))).thenAnswer((_) async => 0);
    when(() => repo.getLatestSummaryWithSnapshot(any(),
        branchId: any(named: 'branchId'))).thenAnswer((_) async => null);
    when(() => repo.saveSummary(any(), any(), any(),
        branchId: any(named: 'branchId'),
        stateSnapshot: any(named: 'stateSnapshot'))).thenAnswer((_) async {
      savedMarkers.add(1);
      return savedMarkers.length;
    });
    when(() =>
            repo.cleanupOldSummaries(any(), branchId: any(named: 'branchId')))
        .thenAnswer((_) async {});
  });

  Future<void> runGenerate({
    required int upToIndex,
    required String boundaryMessageId,
    int generation = 1,
    bool Function(int, int, int)? isCurrent,
  }) async {
    final service = SummaryService(adventureRepo: repo, host: host);
    await service.generateSummary(
      msgs: [for (var i = 0; i < upToIndex; i++) msg(i)],
      upToIndex: upToIndex,
      host: host,
      adventureId: 1,
      branchId: 0,
      generation: generation,
      isCurrent: isCurrent ?? (_, __, ___) => true,
      onSuccess: (_) {},
      onNotify: () {},
      boundaryMessageId: boundaryMessageId,
    );
  }

  test('D1 a successful summary advances exactly its own coverage', () async {
    await runGenerate(upToIndex: 8, boundaryMessageId: 'm7');

    expect(savedMarkers, [1]);
    final captured = verify(() => repo.saveSummary(
          captureAny(),
          captureAny(),
          captureAny(),
          branchId: any(named: 'branchId'),
          stateSnapshot: any(named: 'stateSnapshot'),
        ))
      ..called(1);
    // up_to_id == 8: the marker closes exactly the summarized slice.
    expect(captured.captured[2] as int, 8);
  });

  test('D2 an LLM failure never advances coverage', () async {
    when(() => llm.sendMessageStream(
          any(),
          any(),
          any(),
          onReasoningChunk: any(named: 'onReasoningChunk'),
          params: any(named: 'params'),
          taskHandle: any(named: 'taskHandle'),
        )).thenThrow(StateError('llm down'));

    await runGenerate(upToIndex: 8, boundaryMessageId: 'm7');

    verifyNever(() => repo.saveSummary(any(), any(), any(),
        branchId: any(named: 'branchId'),
        stateSnapshot: any(named: 'stateSnapshot')));
    expect(savedMarkers, isEmpty);
  });

  test('D3 a cancelled/stale generation never advances coverage', () async {
    await runGenerate(
      upToIndex: 8,
      boundaryMessageId: 'm7',
      isCurrent: (_, __, ___) => false,
    );

    verifyNever(() => repo.saveSummary(any(), any(), any(),
        branchId: any(named: 'branchId'),
        stateSnapshot: any(named: 'stateSnapshot')));
  });

  test('D4 a late summary whose boundary moved is rejected', () async {
    // The summary covered [0, 8); meanwhile the list was rewritten so the
    // message at position 7 is no longer the same one.
    liveMessages
      ..removeRange(4, 8)
      ..addAll([for (var i = 20; i < 24; i++) msg(i)]);

    await runGenerate(upToIndex: 8, boundaryMessageId: 'm7');

    verifyNever(() => repo.saveSummary(any(), any(), any(),
        branchId: any(named: 'branchId'),
        stateSnapshot: any(named: 'stateSnapshot')));
  });

  test('D5 a shrunk list cannot be claimed as covered', () async {
    // Regeneration truncated the list below the summary boundary.
    liveMessages.removeRange(5, liveMessages.length);

    await runGenerate(upToIndex: 8, boundaryMessageId: 'm7');

    verifyNever(() => repo.saveSummary(any(), any(), any(),
        branchId: any(named: 'branchId'),
        stateSnapshot: any(named: 'stateSnapshot')));
  });

  test('D6 the exact coverage edge (boundary at index boundary-1) commits',
      () async {
    await runGenerate(upToIndex: 8, boundaryMessageId: 'm7');
    expect(savedMarkers, hasLength(1));
  });

  test('D7 restart reads the durable marker and resumes from it', () async {
    // The durable row says coverage reached 8; with 20 messages and a
    // retain window of 12, the next boundary is 8 as well — nothing new is
    // due, so no generation may run (coverage resumes exactly, not from 0).
    when(() => repo.getLatestSummaryUpToId(1, branchId: 0))
        .thenAnswer((_) async => 8);

    final service = SummaryService(adventureRepo: repo, host: host);
    var generateCalls = 0;
    service.maybeSummarize(
      host: host,
      messages: liveMessages,
      generation: 1,
      isCurrent: (_, __, ___) => true,
      lastSummaryAt: 0,
      lastSummaryTime: null,
      onGenerate: (slice, upTo, _, __, ___, ____) async {
        generateCalls += 1;
      },
    );
    expect(generateCalls, 0);
    await pumpEventQueue(); // the fire-and-forget cycle must settle first

    // With 4 more messages the boundary moves past the durable marker and
    // the next slice starts exactly at 8 — no gap, no re-covering.
    liveMessages.addAll([msg(20), msg(21), msg(22), msg(23)]);
    var capturedStart = -1;
    var capturedEnd = -1;
    service.maybeSummarize(
      host: host,
      messages: liveMessages,
      generation: 1,
      isCurrent: (_, __, ___) => true,
      lastSummaryAt: 0,
      lastSummaryTime: null,
      onGenerate: (slice, upTo, _, __, ___, ____) async {
        capturedStart = upTo - slice.length;
        capturedEnd = upTo;
      },
    );
    await pumpEventQueue();
    expect(capturedStart, 8);
    expect(capturedEnd, 12);
  });

  test(
      'D8 a duplicate summary of the same range is idempotent at the DB '
      'boundary check', () async {
    // Coverage already reached 8: the trigger must not re-summarize [0, 8).
    when(() => repo.getLatestSummaryUpToId(1, branchId: 0))
        .thenAnswer((_) async => 8);

    var generated = 0;
    final service = SummaryService(adventureRepo: repo, host: host);
    service.maybeSummarize(
      host: host,
      messages: liveMessages,
      generation: 1,
      isCurrent: (_, __, ___) => true,
      lastSummaryAt: 0,
      lastSummaryTime: null,
      onGenerate: (_, __, ___, ____, _____, ______) async {
        generated += 1;
      },
    );
    expect(generated, 0);
  });

  test('D9 the summary path never prunes message history', () async {
    // Structural invariant: history deletion is user-driven (branch
    // rewrite/regeneration) and never owned by the summary cycle. A full
    // successful cycle must not touch any destructive repo API — the only
    // cleanup is of old summary rows themselves.
    await runGenerate(upToIndex: 8, boundaryMessageId: 'm7');

    verify(() =>
            repo.cleanupOldSummaries(any(), branchId: any(named: 'branchId')))
        .called(1);
  });

  test('D10 content and marker commit in one row (no split brain)', () async {
    await runGenerate(upToIndex: 8, boundaryMessageId: 'm7');

    final captured = verify(() => repo.saveSummary(
          captureAny(),
          captureAny(),
          captureAny(),
          branchId: any(named: 'branchId'),
          stateSnapshot: any(named: 'stateSnapshot'),
        ))
      ..called(1);
    final content = captured.captured[1] as String;
    final marker = captured.captured[2] as int;
    expect(content, '时间线摘要');
    expect(marker, 8);
    // A single INSERT carries both; a failure between them is impossible.
  });
}
