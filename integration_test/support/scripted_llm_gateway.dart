import 'dart:convert';

import 'package:lt_dialogue/application/llm/llm_gateway.dart';
import 'package:lt_dialogue/models/generation_task_handle.dart';
import 'package:lt_dialogue/models/llm_task.dart';

/// Deterministic [LlmGateway] stand-in for automation.
///
/// It answers exactly the two requests the AI resource-creation pipeline makes
/// — blueprint planning and NDJSON part generation — with fixed, contract-valid
/// payloads, so the whole create→persist→Studio path is exercised without a
/// network, an API key or a real model. Every other method is unsupported by
/// design, so a test can never silently depend on an unmocked real call.
///
/// This is a *test* double. It is never wired into a production composition
/// root and stores no key or fabricated result in user data.
class ScriptedLlmGateway implements LlmGateway {
  ScriptedLlmGateway({
    this.suggestedName = '自动化创建资源',
    this.summary = '确定性测试资源',
    this.partContent = '自动化测试生成的正文内容。',
    this.estimatedPartLength = 800,
    this.planDelay = Duration.zero,
  });

  /// Blueprint name the pipeline will persist as the resource name.
  final String suggestedName;
  final String summary;
  final String partContent;
  final int estimatedPartLength;
  final Duration planDelay;

  int planningCalls = 0;
  int partGenerationCalls = 0;

  @override
  bool get isConfigured => true;

  @override
  Future<String> rawCompletion({
    required String systemPrompt,
    required String instruction,
    int maximumOutputTokens = 4096,
    double temperature = .7,
    LlmTask task = LlmTask.structuredExtraction,
    GenerationTaskHandle? taskHandle,
  }) async {
    // A part-generation prompt embeds the fixed protocol ids; a planning prompt
    // does not. This mirrors the production prompt builder contract.
    final isPartGeneration = systemPrompt.contains('"generation_id"');
    if (!isPartGeneration) {
      planningCalls++;
      if (planDelay > Duration.zero) await Future<void>.delayed(planDelay);
      final sectionId = RegExp(r'允许的 Section ID：([^,\n]+)')
          .firstMatch(systemPrompt)!
          .group(1)!;
      final partId =
          RegExp(r'允许的 Part ID：([^,\n]+)').firstMatch(systemPrompt)!.group(1)!;
      return jsonEncode({
        'suggestedName': suggestedName,
        'summary': summary,
        'sections': [
          {
            'id': sectionId,
            'title': '概览',
            'summary': summary,
            'sortOrder': 0,
            'parts': [
              {
                'id': partId,
                'sectionId': sectionId,
                'title': '正文',
                'generationGoal': summary,
                'estimatedLength': estimatedPartLength,
                'dependencies': <String>[],
                'sortOrder': 0,
              },
            ],
          },
        ],
      });
    }

    partGenerationCalls++;
    final ids = <String, String>{};
    for (final key in [
      'generation_id',
      'resource_id',
      'section_id',
      'part_id',
      'attempt_id',
    ]) {
      ids[key] = RegExp('"$key": "(.*?)"').firstMatch(systemPrompt)!.group(1)!;
    }
    return [
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 0,
        'op': 'start_part',
        'cursor': 0,
      },
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 1,
        'op': 'append_text',
        'text_delta': partContent,
        'cursor': 0,
      },
      {
        'protocol_version': 1,
        ...ids,
        'sequence': 2,
        'op': 'complete_part',
        'cursor': partContent.length,
        'summary': summary,
      },
    ].map(jsonEncode).join('\n');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
      'ScriptedLlmGateway does not implement ${invocation.memberName}');
}
