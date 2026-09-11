import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/model_capabilities.dart';
import 'package:lt_dialogue/models/model_context_capability.dart';

void main() {
  group('ModelCapabilityRegistry — DeepSeek V4.1 Flash', () {
    test('flash reports the V4.1 physical limits and capabilities', () {
      const caps = ModelCapabilityRegistry.deepSeekFlash;
      expect(caps.modelId, 'deepseek-flash');
      expect(caps.contextWindow, 1000000);
      expect(caps.maximumOutputTokens, 384000);
      expect(caps.supportsThinking, isTrue);
      expect(caps.supportsReasoningEffort, isTrue);
      expect(caps.supportsVision, isTrue);
      expect(caps.supportsJsonOutput, isTrue);
      expect(caps.supportsToolCalls, isTrue);
      expect(caps.supportsResponsesApi, isTrue);
      expect(caps.supportsFIM, isTrue);
      expect(caps.supportsPromptCaching, isTrue);
      expect(caps.supportsFilesApi, isFalse);
      expect(caps.thinkingWireStyle, ThinkingWireStyle.deepSeekV41);
      expect(caps.selectableInPicker, isTrue);
      expect(caps.isDeprecated, isFalse);
    });

    test('resolve() finds flash by canonical id and by legacy aliases', () {
      expect(ModelCapabilityRegistry.resolve('deepseek-flash'),
          ModelCapabilityRegistry.deepSeekFlash);
      expect(ModelCapabilityRegistry.resolve('deepseek-v4-flash'),
          ModelCapabilityRegistry.deepSeekFlash);
      expect(ModelCapabilityRegistry.resolve('deepseek-v4-flash-vision-exp'),
          ModelCapabilityRegistry.deepSeekFlash);
    });

    test('canonicalizeAlias rewrites flash aliases only', () {
      expect(ModelCapabilityRegistry.canonicalizeAlias('deepseek-v4-flash'),
          'deepseek-flash');
      expect(
          ModelCapabilityRegistry.canonicalizeAlias(
              'deepseek-v4-flash-vision-exp'),
          'deepseek-flash');
      expect(ModelCapabilityRegistry.canonicalizeAlias('deepseek-flash'),
          'deepseek-flash');
      expect(ModelCapabilityRegistry.canonicalizeAlias('deepseek-v4-pro'),
          'deepseek-v4-pro');
      expect(ModelCapabilityRegistry.canonicalizeAlias('custom-model'),
          'custom-model');
      expect(
          ModelCapabilityRegistry.isLegacyAlias('deepseek-v4-flash'), isTrue);
      expect(ModelCapabilityRegistry.isLegacyAlias('deepseek-flash'), isFalse);
      expect(ModelCapabilityRegistry.isLegacyAlias('deepseek-v4-pro'), isFalse);
    });
  });

  group('ModelCapabilityRegistry — legacy V4 Pro', () {
    test('v4-pro is known, hidden and deprecated', () {
      const caps = ModelCapabilityRegistry.deepSeekV4Pro;
      expect(caps.modelId, 'deepseek-v4-pro');
      expect(caps.isDeprecated, isTrue);
      expect(caps.selectableInPicker, isFalse);
      expect(ModelCapabilityRegistry.isKnownBuiltIn('deepseek-v4-pro'), isTrue);
      expect(ModelCapabilityRegistry.resolve('deepseek-v4-pro'),
          ModelCapabilityRegistry.deepSeekV4Pro);
    });

    test('v4-pro is not offered by the picker', () {
      final picker = ModelCapabilityRegistry.pickerModels();
      expect(picker.map((c) => c.modelId), contains('deepseek-flash'));
      expect(picker.map((c) => c.modelId), isNot(contains('deepseek-v4-pro')));
    });
  });

  group('ModelCapabilityRegistry — unknown and custom models', () {
    test('unknown models fall back conservatively but keep their id', () {
      final caps = ModelCapabilityRegistry.resolve('gpt-4o');
      expect(caps.modelId, 'gpt-4o');
      expect(caps.supportsThinking, isFalse);
      expect(caps.supportsVision, isFalse);
      expect(caps.supportsJsonOutput, isFalse);
      expect(caps.supportsToolCalls, isFalse);
      expect(caps.thinkingWireStyle, ThinkingWireStyle.none);
      expect(caps.capabilitySource, ModelCapabilitySource.conservativeFallback);
      expect(caps.selectableInPicker, isFalse);
    });

    test('empty model id resolves to the conservative placeholder', () {
      final caps = ModelCapabilityRegistry.resolve('   ');
      expect(caps.modelId, 'unknown');
      expect(caps.contextWindow, 8192);
      expect(caps.maximumOutputTokens, 1024);
    });

    test('unknown ids are not treated as known built-ins', () {
      expect(ModelCapabilityRegistry.isKnownBuiltIn('gpt-4o'), isFalse);
      expect(ModelCapabilityRegistry.isKnownBuiltIn('deepseek-flash'), isTrue);
    });
  });

  group('ModelCapabilities.toContextCapability', () {
    test('projects flash capability flags and limits', () {
      final context = ModelCapabilityRegistry.deepSeekFlash
          .toContextCapability(providerId: 'deepseek');
      expect(context.providerId, 'deepseek');
      expect(context.modelId, 'deepseek-flash');
      expect(context.maximumContextTokens, 1000000);
      expect(context.maximumOutputTokens, 384000);
      expect(context.supportsPromptCaching, isTrue);
      expect(context.supportsStructuredOutput, isTrue);
      expect(context.supportsToolCalling, isTrue);
    });

    test('projects conservative fallback with no advanced support', () {
      final context =
          ModelCapabilityRegistry.resolve('gpt-4o').toContextCapability();
      expect(context.maximumContextTokens, 8192);
      expect(context.maximumOutputTokens, 1024);
      expect(context.supportsPromptCaching, isFalse);
      expect(context.supportsStructuredOutput, isFalse);
      expect(context.supportsToolCalling, isFalse);
    });
  });
}
