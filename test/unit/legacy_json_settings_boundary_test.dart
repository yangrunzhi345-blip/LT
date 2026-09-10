import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/models/completion_params.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';

void main() {
  group('ModelContextCapability persisted variants', () {
    test('accepts numeric strings, integral doubles and bool variants', () {
      final capability = ModelContextCapability.fromJson({
        'provider_id': 'p',
        'model_id': 'm',
        'context_window_tokens': '8192',
        'max_output_tokens': 4096.0,
        'supports_prompt_caching': 1,
        'supports_structured_output': 'true',
        'supports_tool_calling': 0,
      });

      expect(capability.maximumContextTokens, 8192);
      expect(capability.maximumOutputTokens, 4096);
      expect(capability.supportsPromptCaching, isTrue);
      expect(capability.supportsStructuredOutput, isTrue);
      expect(capability.supportsToolCalling, isFalse);
    });

    test('falls back to defaults for non-integral legacy values', () {
      final capability = ModelContextCapability.fromJson({
        'context_window_tokens': 'not-a-number',
        'max_output_tokens': 12.5,
      });

      expect(capability.maximumContextTokens, 8192);
      expect(capability.maximumOutputTokens, 1024);
    });
  });

  group('CompletionParams persisted variants', () {
    test('accepts legacy numeric/bool/string variants', () {
      final params = CompletionParams.fromJson({
        'temperature': '0.7',
        'max_tokens': '4096',
        'enable_thinking': 0,
        'reasoning_effort': 'low',
        'response_format': <dynamic, dynamic>{'type': 'json_object'},
      });

      expect(params.temperature, 0.7);
      expect(params.maxTokens, 4096);
      expect(params.enableThinking, isFalse);
      expect(params.reasoningEffort, 'low');
      expect(params.responseFormat, {'type': 'json_object'});
    });

    test('legacy string "false" keeps thinking disabled', () {
      final params = CompletionParams.fromJson({'enable_thinking': 'false'});
      expect(params.enableThinking, isFalse);
    });

    test('invalid legacy max_tokens falls back to the default', () {
      final params = CompletionParams.fromJson({'max_tokens': 'huge'});
      expect(params.maxTokens, 4096);
    });
  });
}
