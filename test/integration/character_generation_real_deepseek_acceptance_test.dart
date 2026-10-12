import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/llm/ai_generator_llm_gateway.dart';
import 'package:lt_dialogue/application/resources/part_generation_coordinator.dart';
import 'package:lt_dialogue/application/resources/resource_blueprint_repository.dart';
import 'package:lt_dialogue/application/resources/resource_creation_contracts.dart';
import 'package:lt_dialogue/application/resources/resource_creation_pipeline.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/core/debug/generation_diagnostics.dart';
import 'package:lt_dialogue/domain/resources/resource_blueprint.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/key_vault.dart';
import 'package:lt_dialogue/services/llm_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 受控真实 DeepSeek API 验收（角色卡生成弹性预算重构）。
///
/// 仅当 `LT_REAL_DEEPSEEK=1` 时执行；API Key 从真实应用数据库
/// （api_keys 表，provider=deepseek，KeyVault 加密）只读加载并解密，
/// 绝不打印或记录明文 Key。所有 SQLite 写入落在临时目录，
/// 用户真实数据库从不写入。
///
/// 预算护栏（硬限制）：
/// - 逻辑生成请求 ≤ 10 次（`LT_REAL_DEEPSEEK_MAX_REQUESTS` 可下调）。
/// - 按官方峰值价格（V4.1 Flash：输入 miss $0.30/M、输出 $1.20/M）
///   保守估算，累计费用上限 $1.00，超限立即停止发起新请求。
/// - 每次调用记录 model、params、tokens、finish_reason、耗时与估算费用。
void main() {
  // 注意：这里绝不能初始化 TestWidgetsFlutterBinding——它会拦截所有
  // dart:io HttpClient（本地回 400），真实 API 请求就发不出去了。
  // 本 rig 是纯 Dart 链路（sqflite ffi + http），无需 binding。
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  setUpAll(() {
    GenerationDiagnostics.printingEnabled = false;
  });

  final budget = _RealApiBudget();

  tearDownAll(() {
    budget.printSummary();
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_real_deepseek_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test(
    'PHASE A: 小型 Part（目标 600 字）— NDJSON 协议 / validator / SQLite 提交',
    () async {
      if (budget.exhausted) return _markSkipped('A', budget);
      final rig = await _RealRig.build(
        budget: budget,
        name: 'REAL-A 小型 Part',
        targetCapacity: 600,
        partLengths: const [600],
      );
      final completed = await rig.run();
      budget.printSummary();

      expect(completed, isTrue, reason: 'PHASE A 生成应完成');
      expect(rig.committedParts.length, 1);
      final content = rig.committedParts.values.single;
      expect(content.trim(), isNotEmpty);
      // 非思考模式必须生效：无 reasoning 输出。
      for (final r in budget.records) {
        expect(r.thinkingRequested, isFalse, reason: '任务策略禁用思考');
        expect(r.reasoningChars, 0, reason: '非思考模式不应产生 reasoning_content');
        expect(r.maxTokens, 4096);
        expect(r.temperature, 0.7);
      }
      // NDJSON 协议：至少 start/append/complete 三条 patch。
      expect(rig.patchCount, greaterThanOrEqualTo(3));
      final record = budget.records.single;
      expect(record.finishReason, 'stop');
      expect(record.promptTokens, greaterThan(0));
      expect(record.completionTokens, greaterThan(0));
      _printJson('PHASE_A_RESULT', {
        'committedChars': content.length,
        'target': 600,
        'deviation': content.length - 600,
        'patches': rig.patchCount,
        'finishReason': record.finishReason,
      });
      rig.dispose();
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: _gate,
  );

  test(
    'PHASE B: 近 3000 字 Part（目标 2800 字）— 4096 token 预算与弹性保存',
    () async {
      if (budget.exhausted) return _markSkipped('B', budget);
      final rig = await _RealRig.build(
        budget: budget,
        name: 'REAL-B 长 Part',
        targetCapacity: 2800,
        partLengths: const [2800],
      );
      final completed = await rig.run();
      budget.printSummary();

      if (!completed) {
        // 截断/协议失败必须被分类，不允许“成功但为空”。
        expect(rig.committedParts, isEmpty, reason: '失败时不得静默提交被截断正文');
        fail('PHASE B 未完成：${budget.classifyFailure(rig.lastError)}'
            '（lastError=${rig.lastError}）');
      }
      final content = rig.committedParts.values.single;
      final record = budget.records.last;
      // 单段传输上限 3000 与累计上限 C=3360 双重约束。
      expect(content.length, lessThanOrEqualTo(3000));
      expect(content.length, lessThanOrEqualTo(3360));
      _printJson('PHASE_B_RESULT', {
        'committedChars': content.length,
        'target': 2800,
        'elasticCeiling': 3360,
        'exceedsTargetButSaved': content.length > 2800,
        'patches': rig.patchCount,
        'finishReason': record.finishReason,
        'completionTokens': record.completionTokens,
      });
      rig.dispose();
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: _gate,
  );

  test(
    'PHASE C: 8000 字多 Part（4×2000）— 累计弹性预算 C=9600 与重试安全',
    () async {
      if (budget.exhausted) return _markSkipped('C', budget);
      final rig = await _RealRig.build(
        budget: budget,
        name: 'REAL-C 多 Part 8000',
        targetCapacity: 8000,
        partLengths: const [2000, 2000, 2000, 2000],
      );
      final completed = await rig.run(maxRetriesPerPart: 1);
      budget.printSummary();

      if (!completed) {
        fail('PHASE C 未完成：${budget.classifyFailure(rig.lastError)}'
            '（lastError=${rig.lastError}）');
      }
      final total =
          rig.committedParts.values.fold<int>(0, (sum, c) => sum + c.length);
      // 累计硬上限 C=9600 必须被尊重；软目标 T=8000 允许自然超出。
      expect(total, lessThanOrEqualTo(9600), reason: '累计正文不得超过弹性上限 C');
      expect(total, greaterThan(4000), reason: '四段合计应达到实质内容量');
      _printJson('PHASE_C_RESULT', {
        'totalChars': total,
        'target': 8000,
        'elasticCeiling': 9600,
        'exceedsTargetButSaved': total > 8000,
        'parts': {
          for (final e in rig.committedParts.entries) e.key: e.value.length,
        },
        'logicalRequests': budget.records.length,
      });
      rig.dispose();
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _gate,
  );

  test(
    'PHASE D: 20000 字完整角色卡 — 预算内无法完成则显式 NOT VERIFIED',
    () async {
      // 20000 字 ≈ 10 段 × 2000 字 ≈ 10+ 次请求，超出 10 次请求护栏。
      _printJson('PHASE_D_RESULT', {
        'status': 'NOT VERIFIED',
        'reason': '10 次请求护栏内无法完成 20000 字完整角色卡生成，'
            '按授权不得伪造结果',
      });
    },
    skip: _gate,
  );

  test(
    'PHASE E: finish_reason=length 截断识别探针（maxTokens=64 强制截断）',
    () async {
      if (budget.exhausted) return _markSkipped('E', budget);
      final apiKey = await _RealRig.loadRealApiKey();
      final llm = _RecordingLLMService(
        LLMConfig(
          provider: LLMProvider.deepseek,
          apiKey: apiKey,
          baseUrl: Platform.environment['LT_REAL_DEEPSEEK_BASE_URL'] ??
              'https://api.deepseek.com',
          model: Platform.environment['LT_REAL_DEEPSEEK_MODEL'] ??
              'deepseek-flash',
        ),
        budget,
      );
      final gateway = AiGeneratorLlmGateway(
        () => throw UnimplementedError(),
        llmResolver: () => llm,
      );
      // 用真实 NDJSON 协议提示词 + 极小输出预算，强制真实截断。
      Object? caught;
      try {
        await gateway.rawCompletion(
          systemPrompt: '只输出 NDJSON Patch 行。'
              '首行 {"sequence":0,"op":"start_part"}，'
              '正文用 append_text 输出一篇 2000 字的合成散文，'
              '末行 {"sequence":2,"op":"complete_part","summary":"摘要"}。',
          instruction: '开始生成，正文主题为合成测试设定中的云岚列岛。',
          maximumOutputTokens: 64,
          task: LlmTask.resourcePartGeneration,
        );
      } catch (error) {
        caught = error;
      }
      budget.printSummary();
      // 64 token 必然截断 NDJSON：生产链路必须抛出可识别的截断异常，
      // 且记录的 finish_reason 为 length（而非静默返回半截协议）。
      expect(caught, isA<LLMResponseIncompleteException>(),
          reason: '截断响应必须被分类为 LLMResponseIncompleteException');
      final incomplete = caught! as LLMResponseIncompleteException;
      _printJson('PHASE_E_RESULT', {
        'finishReason': incomplete.result.finishReason.stableValue,
        'completionTokens': incomplete.result.completionTokens ?? 0,
        'contentChars': incomplete.result.content.length,
      });
      expect(incomplete.result.finishReason.stableValue, 'length');
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: _gate,
  );
}

String? get _gate => Platform.environment['LT_REAL_DEEPSEEK'] == '1'
    ? null
    : 'Real DeepSeek acceptance requires LT_REAL_DEEPSEEK=1';

void _markSkipped(String phase, _RealApiBudget budget) {
  // ignore: avoid_print
  print('[_REAL_DEEPSEEK] PHASE $phase SKIPPED: 请求/费用预算已耗尽'
      '（requests=${budget.records.length}）');
}

void _printJson(String tag, Map<String, Object?> data) {
  // ignore: avoid_print
  print('[_REAL_DEEPSEEK] $tag ${jsonEncode(data)}');
}

/// 一次真实 HTTP 调用的观测记录（不含任何 Key/凭证）。
class _RealRequestRecord {
  _RealRequestRecord({
    required this.seq,
    required this.model,
    required this.maxTokens,
    required this.temperature,
    required this.thinkingRequested,
    required this.finishReason,
    required this.promptTokens,
    required this.completionTokens,
    required this.promptCacheHitTokens,
    required this.promptCacheMissTokens,
    required this.reasoningChars,
    required this.contentChars,
    required this.elapsedMs,
    required this.errorKind,
    required this.errorSummary,
  });

  final int seq;
  final String model;
  final int maxTokens;
  final double temperature;
  final bool thinkingRequested;
  final String finishReason;
  final int promptTokens;
  final int completionTokens;
  final int promptCacheHitTokens;
  final int promptCacheMissTokens;
  final int reasoningChars;
  final int contentChars;
  final int elapsedMs;
  final String errorKind;
  final String errorSummary;

  /// 保守估算：全部输入按 cache-miss 峰值计价（V4.1 Flash）。
  double get costUsd =>
      (promptTokens * _RealApiBudget.inputMissUsdPerM +
          completionTokens * _RealApiBudget.outputUsdPerM) /
      1000000.0;

  Map<String, Object?> toJson() => {
        'seq': seq,
        'model': model,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'thinkingRequested': thinkingRequested,
        'finishReason': finishReason,
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'promptCacheHitTokens': promptCacheHitTokens,
        'promptCacheMissTokens': promptCacheMissTokens,
        'reasoningChars': reasoningChars,
        'contentChars': contentChars,
        'elapsedMs': elapsedMs,
        'costUsd': costUsd.toStringAsFixed(5),
        if (errorKind.isNotEmpty) 'errorKind': errorKind,
        if (errorSummary.isNotEmpty) 'errorSummary': errorSummary,
      };
}

/// 请求与费用硬护栏。
class _RealApiBudget {
  static const int maxRequests = 10;
  static const double maxCostUsd = 1.00;

  /// DeepSeek V4.1 Flash 峰值价（USD / M tokens）：输入 miss、输出。
  static const double inputMissUsdPerM = 0.30;
  static const double outputUsdPerM = 1.20;

  final List<_RealRequestRecord> records = [];
  int _seq = 0;
  String? stopReason;

  bool get exhausted => stopReason != null;

  void beforeRequest() {
    if (records.length >= maxRequests) {
      stopReason = 'REQUEST_LIMIT';
      throw _BudgetExhaustedException('已达逻辑请求上限 $maxRequests，停止发起新请求');
    }
  }

  void record(_RealRequestRecord record) {
    records.add(record);
    final total = records.fold<double>(0, (s, r) => s + r.costUsd);
    if (total > maxCostUsd) {
      stopReason = 'COST_LIMIT';
    }
  }

  double get totalCostUsd => records.fold<double>(0, (s, r) => s + r.costUsd);

  void printSummary() {
    // ignore: avoid_print
    print('[_REAL_DEEPSEEK] SUMMARY ${jsonEncode({
          'requests': records.length,
          'totalCostUsd': totalCostUsd.toStringAsFixed(5),
          'stopReason': stopReason,
          'records': [for (final r in records) r.toJson()],
        })}');
  }

  String classifyFailure(Object? error) {
    if (error == null) return 'unknown';
    final text = error.toString();
    if (error is _BudgetExhaustedException) return '累计生成预算超限';
    if (text.contains('LLMResponseIncompleteException')) return '模型输出长度截断';
    if (text.contains('ApiError') || text.contains('HTTP'))
      return 'API HTTP 错误';
    if (text.contains('GenerationPatchParseException') ||
        text.contains('PatchSequenceGapException') ||
        text.contains('PatchCursorMismatchException')) {
      return 'NDJSON 协议错误';
    }
    if (text.contains('PartGenerationValidationException')) {
      return text.contains('generation_budget') ? '累计生成预算超限' : 'UTF-16 正文长度超限';
    }
    if (text.contains('DatabaseException') || text.contains('SQLite')) {
      return 'SQLite 保存失败';
    }
    if (text.contains('TimeoutException') || text.contains('cancelled')) {
      return '任务超时或取消';
    }
    return '其他（未分类）';
  }
}

final class _BudgetExhaustedException implements Exception {
  _BudgetExhaustedException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 记录型 LLMService：在真实 HTTP 链路上逐次捕获 usage 与 finish_reason。
class _RecordingLLMService extends LLMService {
  _RecordingLLMService(super.config, this.budget);

  final _RealApiBudget budget;

  @override
  Future<LLMStreamResult> sendMessageStreamDetailed(
    List<Map<String, String>> messages,
    void Function(String chunk) onChunk,
    void Function() onDone, {
    void Function(String reasoningChunk)? onReasoningChunk,
    CompletionParams params = const CompletionParams(),
    GenerationTaskHandle? taskHandle,
  }) async {
    budget.beforeRequest();
    final sw = Stopwatch()..start();
    final seq = ++budget._seq;
    try {
      final result = await super.sendMessageStreamDetailed(
        messages,
        onChunk,
        onDone,
        onReasoningChunk: onReasoningChunk,
        params: params,
        taskHandle: taskHandle,
      );
      sw.stop();
      budget.record(_RealRequestRecord(
        seq: seq,
        model: config.model,
        maxTokens: params.maxTokens,
        temperature: params.temperature,
        thinkingRequested: params.enableThinking,
        finishReason: result.finishReason.stableValue,
        promptTokens: result.promptTokens ?? 0,
        completionTokens: result.completionTokens ?? 0,
        promptCacheHitTokens: result.promptCacheHitTokens ?? 0,
        promptCacheMissTokens: result.promptCacheMissTokens ?? 0,
        reasoningChars: result.reasoningContent?.length ?? 0,
        contentChars: result.content.length,
        elapsedMs: sw.elapsedMilliseconds,
        errorKind: '',
        errorSummary: '',
      ));
      return result;
    } catch (error) {
      sw.stop();
      final detail = error is LLMResponseIncompleteException
          ? 'finish=${error.result.finishReason.stableValue} '
              'completionTokens=${error.result.completionTokens}'
          : error.runtimeType.toString();
      budget.record(_RealRequestRecord(
        seq: seq,
        model: config.model,
        maxTokens: params.maxTokens,
        temperature: params.temperature,
        thinkingRequested: params.enableThinking,
        finishReason: error is LLMResponseIncompleteException
            ? error.result.finishReason.stableValue
            : 'error',
        promptTokens: error is LLMResponseIncompleteException
            ? (error.result.promptTokens ?? 0)
            : 0,
        completionTokens: error is LLMResponseIncompleteException
            ? (error.result.completionTokens ?? 0)
            : 0,
        promptCacheHitTokens: 0,
        promptCacheMissTokens: 0,
        reasoningChars: error is LLMResponseIncompleteException
            ? (error.result.reasoningContent?.length ?? 0)
            : 0,
        contentChars: 0,
        elapsedMs: sw.elapsedMilliseconds,
        errorKind: budget.classifyFailure(error),
        errorSummary: detail,
      ));
      rethrow;
    }
  }
}

/// 真实链路 rig：真实 SQLite 仓库 + 真实 LlmGateway + 真实 coordinator，
/// 仅隔离用户真实数据库（写入临时目录）与 API Key（只读解密，不打印）。
class _RealRig {
  _RealRig._({
    required this.gateway,
    required this.coordinator,
    required this.taskRepository,
    required this.resourceId,
    required this.partIds,
  });

  final AiGeneratorLlmGateway gateway;
  final PartGenerationCoordinator coordinator;
  final PartGenerationTaskRepositoryImpl taskRepository;
  final ResourceId resourceId;
  final List<String> partIds;

  final Map<String, String> committedParts = {};
  int patchCount = 0;
  Object? lastError;

  /// 从真实应用数据库只读解密 DeepSeek Key（绝不打印）。
  static Future<String> loadRealApiKey() async {
    final dbPath = Platform.environment['LT_REAL_DEEPSEEK_DB'] ??
        '${Directory.current.path}'
            '/.dart_tool/sqflite_common_ffi/databases/adventures.db';
    final db = await openDatabase(dbPath, readOnly: true);
    try {
      final rows = await db.query(
        'api_keys',
        columns: ['encrypted_key'],
        where: 'provider = ?',
        whereArgs: ['deepseek'],
        limit: 1,
      );
      final encrypted = rows.isEmpty ? '' : (rows.first['encrypted_key'] ?? '');
      final key = KeyVault.decrypt(encrypted.toString());
      if (key.isEmpty) {
        throw StateError('无法从真实数据库解密 DeepSeek Key（$dbPath）');
      }
      return key;
    } finally {
      await db.close();
    }
  }

  static Future<_RealRig> build({
    required _RealApiBudget budget,
    required String name,
    required int targetCapacity,
    required List<int> partLengths,
  }) async {
    final apiKey = await loadRealApiKey();
    final model =
        Platform.environment['LT_REAL_DEEPSEEK_MODEL'] ?? 'deepseek-flash';
    final baseUrl = Platform.environment['LT_REAL_DEEPSEEK_BASE_URL'] ??
        'https://api.deepseek.com';

    final llm = _RecordingLLMService(
      LLMConfig(
        provider: LLMProvider.deepseek,
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
      ),
      budget,
    );
    final gateway = AiGeneratorLlmGateway(
      () => throw UnimplementedError('真实验收只走 rawCompletion/stream 路径'),
      llmResolver: () => llm,
    );

    Future<Database> getDb() => DatabaseService.database;
    final treeRepository = ResourceTreeRepositoryImpl(getDb: getDb);
    final revisionRepository = ResourceRevisionRepositoryImpl(getDb: getDb);
    final revisionCapture = RevisionCaptureEngine(
      revisionRepository: revisionRepository,
      treeBoundary: treeRepository,
    );
    final blueprintRepository = ResourceBlueprintRepositoryImpl(
      getDb: getDb,
      treeRepository: treeRepository,
      revisionCapture: revisionCapture,
    );
    final taskRepository = PartGenerationTaskRepositoryImpl(
      getDb: getDb,
      revisionBoundary: revisionCapture,
    );
    final pipeline = ResourceCreationPipeline(
      getDb: getDb,
      hasAiCredentials: () => true,
      treeRepository: treeRepository,
      blueprintRepository: blueprintRepository,
      generationTaskRepository: taskRepository,
      revisionCapture: revisionCapture,
    );

    final creation = await pipeline.create(ResourceCreationRequest(
      resourceType: ResourceType.character,
      method: CreationMethod.aiReference,
      name: name,
      idempotencyKey: 'real_${DateTime.now().microsecondsSinceEpoch}',
      referenceSource: ReferenceSource.text(_syntheticReference()),
    ));

    final bpParts = <BlueprintPart>[];
    String? previous;
    for (var i = 0; i < partLengths.length; i++) {
      final partId = 'part_${i + 1}';
      bpParts.add(BlueprintPart(
        id: partId,
        sectionId: 'sec_1',
        title: '第${i + 1}节',
        generationGoal: '生成角色卡第${i + 1}节正文',
        estimatedLength: partLengths[i],
        dependencies: previous != null ? [previous] : const <String>[],
      ));
      previous = partId;
    }

    final blueprint = ResourceBlueprint(
      blueprintId: 'bp_real_${DateTime.now().microsecondsSinceEpoch}',
      sessionId: creation.sessionId!,
      resourceType: ResourceType.character,
      suggestedName: name,
      summary: '受控真实 API 验收合成资源',
      targetCapacity: targetCapacity,
      sections: [
        BlueprintSection(
          id: 'sec_1',
          title: '角色档案',
          parts: bpParts,
        ),
      ],
    );
    await blueprintRepository.saveBlueprint(blueprint);
    final confirmation = await blueprintRepository.confirmBlueprint(
      blueprintId: blueprint.blueprintId,
    );

    final coordinator = PartGenerationCoordinator(
      taskRepository: taskRepository,
      blueprintRepository: blueprintRepository,
      pipeline: pipeline,
      gateway: gateway,
      maxConcurrency: 1,
    );

    final rig = _RealRig._(
      gateway: gateway,
      coordinator: coordinator,
      taskRepository: taskRepository,
      resourceId: confirmation.resourceId,
      partIds: bpParts.map((p) => p.id).toList(),
    );
    return rig;
  }

  Future<bool> run({int maxRetriesPerPart = 1}) async {
    try {
      return await coordinator.generateAllParts(
        blueprintId: (await _blueprintIdOf())!,
        maxRetriesPerPart: maxRetriesPerPart,
        callbacks: PartGenerationLifecycleCallbacks(
          onPatchReceived: ({
            required generationId,
            required resourceId,
            required partId,
            required taskId,
            required attemptId,
            required patch,
            required accumulatedLength,
          }) {
            patchCount++;
          },
          onPartCommitted: ({
            required generationId,
            required resourceId,
            required partId,
            required taskId,
            required attemptId,
            required characterCount,
          }) async {
            final parts = await taskRepository.getPartsContent([partId.value]);
            committedParts[partId.value] = parts[partId.value]?.content ?? '';
          },
        ),
      );
    } catch (error) {
      lastError = error;
      return false;
    }
  }

  Future<String?> _blueprintIdOf() async {
    // build() 已确认 blueprint；这里通过任务行反查 blueprintId。
    final tasks = await taskRepository.findTasksForResource(resourceId.value);
    return tasks.isEmpty ? null : tasks.first.blueprintId;
  }

  void dispose() {}
}

/// 合成参考材料（纯测试文本，不含任何真实用户资料）。
String _syntheticReference() => '''
【合成测试设定】
在浮空群岛「云岚列岛」上，风系术士依托「引风者」行会维持群岛间的航线。
行会总部「银岚塔」立于主岛中央，塔顶的风罗盘指引商船穿过乱流带。
近来乱流带频发「黑风潮」，商路受阻，行会内部对应对方案产生分歧。
''';
