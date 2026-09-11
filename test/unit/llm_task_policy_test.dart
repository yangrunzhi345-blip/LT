import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/llm_task.dart';
import 'package:lt_dialogue/models/model_capabilities.dart';
import 'package:lt_dialogue/services/llm_task_policy.dart';

void main() {
  const resolver = LlmTaskResolver();
  const flash = ModelCapabilityRegistry.deepSeekFlash;
  // A model with no JSON/thinking support (custom provider fallback).
  final plain = ModelCapabilityRegistry.resolve('custom-model');

  group('LlmTaskResolver — thinking policy', () {
    for (final task in const [
      LlmTask.importExtraction,
      LlmTask.structuredExtraction,
      LlmTask.summary,
      LlmTask.translation,
      LlmTask.visionExtraction,
      LlmTask.runtimeStateAnalysis,
      LlmTask.narrativeSupplement,
    ]) {
      test('$task is always non-thinking', () {
        final params = resolver.resolve(
          task: task,
          capabilities: flash,
          // Even if the user enabled thinking, helpers stay off.
          userParams: const CompletionParams(enableThinking: true),
        );
        expect(params.enableThinking, isFalse);
      });
    }

    for (final task in const [
      LlmTask.worldviewFast,
      LlmTask.characterFast,
      LlmTask.worldviewDeep,
      LlmTask.characterDeep,
      LlmTask.adventureNarrative,
      LlmTask.adventurePlanning,
    ]) {
      test('$task follows the user thinking toggle', () {
        final on = resolver.resolve(
          task: task,
          capabilities: flash,
          userParams: const CompletionParams(enableThinking: true),
        );
        expect(on.enableThinking, isTrue);

        final off = resolver.resolve(
          task: task,
          capabilities: flash,
          userParams: const CompletionParams(enableThinking: false),
        );
        expect(off.enableThinking, isFalse);
      });
    }

    test('thinking is suppressed when the model does not support it', () {
      final params = resolver.resolve(
        task: LlmTask.adventureNarrative,
        capabilities: plain,
        userParams: const CompletionParams(enableThinking: true),
      );
      expect(params.enableThinking, isFalse);
    });
  });

  group('LlmTaskResolver — JSON output', () {
    test('structured tasks request JSON when supported', () {
      final params = resolver.resolve(
        task: LlmTask.structuredExtraction,
        capabilities: flash,
      );
      expect(params.responseFormat, {'type': 'json_object'});
    });

    test('prose tasks never request JSON', () {
      final params = resolver.resolve(
        task: LlmTask.translation,
        capabilities: flash,
      );
      expect(params.responseFormat, isNull);
    });

    test('JSON is suppressed when the model does not support it', () {
      final params = resolver.resolve(
        task: LlmTask.structuredExtraction,
        capabilities: plain,
      );
      expect(params.responseFormat, isNull);
    });

    test('forceJson can enable and disable explicitly', () {
      expect(
        resolver
            .resolve(
              task: LlmTask.translation,
              capabilities: flash,
              forceJson: true,
            )
            .responseFormat,
        {'type': 'json_object'},
      );
      expect(
        resolver
            .resolve(
              task: LlmTask.structuredExtraction,
              capabilities: flash,
              forceJson: false,
            )
            .responseFormat,
        isNull,
      );
    });
  });

  group('LlmTaskResolver — budgets and immutability', () {
    test('output budget override wins over the user value', () {
      final params = resolver.resolve(
        task: LlmTask.adventureNarrative,
        capabilities: flash,
        userParams: const CompletionParams(maxTokens: 2048),
        maximumOutputTokens: 8192,
      );
      expect(params.maxTokens, 8192);
    });

    test('user temperature is preserved when the policy has no override', () {
      final params = resolver.resolve(
        task: LlmTask.translation,
        capabilities: flash,
        userParams: const CompletionParams(temperature: 0.42, topP: 0.5),
      );
      expect(params.temperature, 0.42);
      expect(params.topP, 0.5);
    });

    test('resolver never mutates the supplied user params', () {
      const user = CompletionParams(
        enableThinking: true,
        temperature: 1.3,
        maxTokens: 1234,
      );
      resolver.resolve(
        task: LlmTask.translation,
        capabilities: flash,
        userParams: user,
        maximumOutputTokens: 64,
      );
      expect(user.enableThinking, isTrue);
      expect(user.temperature, 1.3);
      expect(user.maxTokens, 1234);
    });

    test('vision task carries a detail hint', () {
      expect(
        LlmTaskPolicyTable.policyFor(LlmTask.visionExtraction).visionDetail,
        'high',
      );
    });
  });
}
