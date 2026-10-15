import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/debug/generation_diagnostics.dart';
import 'package:lt_dialogue/models/llm_task.dart';

final class _Unprintable {
  @override
  String toString() => throw StateError('must never stringify arbitrary data');
}

void main() {
  group('GenerationDiagnostics safe LLM channel', () {
    late DebugPrintCallback previousPrinter;
    final output = <String>[];
    setUp(() {
      output.clear();
      previousPrinter = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) output.add(message);
      };
    });
    tearDown(() => debugPrint = previousPrinter);

    test('should honor the compile-time opt-in independently of debug mode',
        () {
      expect(GenerationDiagnostics.safeLlmEnabled,
          const bool.fromEnvironment('LT_SAFE_LLM_DIAGNOSTICS'));
      GenerationDiagnostics.instance.markSafeLlm('ATTEMPT_START',
          attemptSequence: 1,
          details: {'task': LlmTask.resourceBlueprintPlanning});
      expect(output, hasLength(GenerationDiagnostics.safeLlmEnabled ? 1 : 0));
    });

    test('should validate build metadata before logging it', () {
      GenerationDiagnostics.instance
          .markSafeLlm('ATTEMPT_START', attemptSequence: 1);
      if (!GenerationDiagnostics.safeLlmEnabled) {
        expect(output, isEmpty);
        return;
      }
      final record =
          jsonDecode(output.single.substring('[lt-safe-llm] '.length))
              as Map<String, dynamic>;
      const sha = String.fromEnvironment('LT_BUILD_GIT_SHA');
      const version = String.fromEnvironment('LT_BUILD_VERSION');
      expect(record['gitSha'], sha == 'a3458d9' ? sha : 'unknown');
      expect(record['version'], version == '1.2.08+30' ? version : 'unknown');
    });

    test('should discard arbitrary labels and invalid attempt sequences', () {
      GenerationDiagnostics.instance
        ..markSafeLlm('private-label', attemptSequence: 1)
        ..markSafeLlm('ATTEMPT_DONE', attemptSequence: 0)
        ..markSafeLlm('ATTEMPT_DONE', attemptSequence: -1);
      expect(output, isEmpty);
    });

    test('should strictly filter field types and unknown strings', () {
      GenerationDiagnostics.instance
          .markSafeLlm('ATTEMPT_FAILED', attemptSequence: 17, details: {
        'attemptSequence': 'private-id',
        'event': 'private-event',
        'task': 'private-task',
        'stackTrace': StackTrace.current,
        'message': 'private-message',
        'body': 'private-body',
        'headers': {'Authorization': 'private-key'},
        'endpointPath': '/private-path',
        'endpointHost': 'example.invalid/private-query',
        'model': 'model\nprivate-model',
        'provider': 'private-provider',
        'finishReason': 'private-finish',
        'failureClass': 'private-failure',
        'retryReason': 'private-retry',
        'max_tokens': 'private-tokens',
        'contentChars': -1,
        'promptTokens': 1.5,
        'httpStatus': 999,
        'responseCompleted': 'private-completed',
        'unknown': _Unprintable(),
      });
      expect(output.join(), isNot(contains('private')));
      if (!GenerationDiagnostics.safeLlmEnabled) {
        expect(output, isEmpty);
        return;
      }
      final record =
          jsonDecode(output.single.substring('[lt-safe-llm] '.length))
              as Map<String, dynamic>;
      expect(record.keys.toSet(), {
        'event',
        'attemptSequence',
        'platform',
        'buildMode',
        'gitSha',
        'version',
      });
      expect(record['attemptSequence'], 17);
    });

    test('should bound free-form model and host identifiers', () {
      GenerationDiagnostics.instance
          .markSafeLlm('ENDPOINT', attemptSequence: 1, details: {
        'model': 'm' * 129,
        'endpointHost': 'h' * 254,
      });
      if (!GenerationDiagnostics.safeLlmEnabled) {
        expect(output, isEmpty);
        return;
      }
      final record =
          jsonDecode(output.single.substring('[lt-safe-llm] '.length))
              as Map<String, dynamic>;
      expect(record.containsKey('model'), isFalse);
      expect(record.containsKey('endpointHost'), isFalse);
    });

    test('should ignore an attemptSequence injected through details', () {
      GenerationDiagnostics.instance.markSafeLlm('ATTEMPT_DONE',
          attemptSequence: 23, details: {'attemptSequence': 999, 'attempt': 4});
      if (!GenerationDiagnostics.safeLlmEnabled) {
        expect(output, isEmpty);
        return;
      }
      final record =
          jsonDecode(output.single.substring('[lt-safe-llm] '.length))
              as Map<String, dynamic>;
      // The named parameter is authoritative; `attemptSequence` is not part of
      // any allowlist set, so a caller cannot rewrite the sequence via details.
      expect(record['attemptSequence'], 23);
      expect(record['attempt'], 4);
    });

    test('should never throw on hostile values under allowlisted keys', () {
      final hostile = <String, Object?>{
        'contentChars': _Unprintable(),
        'promptTokens': double.nan,
        'elapsedMs': double.infinity,
        'model': _Unprintable(),
        'endpointHost': _Unprintable(),
        'httpStatus': _Unprintable(),
        'finishReason': _Unprintable(),
        'task': 'not-a-task',
      };
      expect(
          () => GenerationDiagnostics.instance.markSafeLlm('ATTEMPT_FAILED',
              attemptSequence: 5, details: hostile),
          returnsNormally);
      if (!GenerationDiagnostics.safeLlmEnabled) {
        expect(output, isEmpty);
        return;
      }
      final record =
          jsonDecode(output.single.substring('[lt-safe-llm] '.length))
              as Map<String, dynamic>;
      expect(record.keys.toSet(), {
        'event',
        'attemptSequence',
        'platform',
        'buildMode',
        'gitSha',
        'version',
      });
      expect(record['attemptSequence'], 5);
    });

    test('should reject endpoint hosts that carry userinfo, path or query', () {
      GenerationDiagnostics.instance
          .markSafeLlm('ENDPOINT', attemptSequence: 1, details: {
        'endpointHost': 'user:password@example.invalid',
        'model': 'deepseek-flash',
      });
      if (!GenerationDiagnostics.safeLlmEnabled) {
        expect(output, isEmpty);
        return;
      }
      final record =
          jsonDecode(output.single.substring('[lt-safe-llm] '.length))
              as Map<String, dynamic>;
      expect(record.containsKey('endpointHost'), isFalse);
      // A provider model name is the user's own configured value and stays
      // admissible; it can never contain credentials because the character
      // class excludes `@ ? #` and whitespace.
      expect(record['model'], 'deepseek-flash');
    });
  });
}
