import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/tts/speech_plan.dart';
import 'package:lt_dialogue/domain/tts/tts_errors.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/domain/tts/tts_voices.dart';
import 'package:lt_dialogue/services/tts/tts_model_catalog.dart';
import 'package:lt_dialogue/services/tts/tts_voice_binding_store.dart';
import 'package:lt_dialogue/services/tts/tts_voice_resolver.dart';

class _FakeRegistry implements TtsInstalledModelRegistry {
  _FakeRegistry(this.models);

  final List<TtsModelDescriptor> models;
  bool installed = true;

  @override
  bool isModelInstalled(String modelId) =>
      installed && models.any((m) => m.modelId == modelId);

  @override
  List<TtsModelDescriptor> get installedModelDescriptors =>
      installed ? models : const <TtsModelDescriptor>[];
}

TtsModelDescriptor _descriptor() => TtsModelDescriptor(
      modelId: 'test-model',
      version: 'v1',
      displayName: 'Test',
      engineFamily: 'kokoro',
      voiceFamily: 'family',
      languages: const <String>['zh-CN'],
      speakerCount: 4,
      downloadUri: Uri.parse('https://example.invalid/test.tar.bz2'),
      downloadSizeBytes: 10,
      license: 'Apache-2.0',
      licenseUri: null,
      archiveFormat: TtsArchiveFormat.tarBz2,
      requiredFiles: const <TtsFileSpec>[],
      modelFileName: const <String>['model.onnx'],
      capabilities: TtsVoiceCapabilities.kokoro,
      integrity: const TtsModelIntegrity.officialSha256('x'),
    );

void main() {
  late TtsModelCatalog catalog;
  late _FakeRegistry registry;

  setUp(() {
    catalog = TtsModelCatalog(models: <TtsModelDescriptor>[_descriptor()]);
    registry = _FakeRegistry(<TtsModelDescriptor>[_descriptor()]);
  });

  TtsVoiceResolver resolverWith(TtsVoicePreferences prefs) => TtsVoiceResolver(
        catalog: catalog,
        bindings: TtsVoiceBindingStore(initial: prefs),
        registry: registry,
      );

  test('system mode always resolves to the system backend', () {
    final resolver = resolverWith(
      const TtsVoicePreferences(mode: TtsBackendKind.system),
    );
    final resolution = resolver.resolve(role: SpeechRole.narration);
    expect(resolution.isSystem, isTrue);
    expect(resolution.target, isNull);
  });

  test('narrator binding resolves to a neural target', () {
    final resolver = resolverWith(
      const TtsVoicePreferences(
        mode: TtsBackendKind.neural,
        narratorVoiceId: 'family:s1',
      ),
    );
    final resolution = resolver.resolve(role: SpeechRole.narration);
    expect(resolution.target, isNotNull);
    expect(resolution.target!.isNeural, isTrue);
    expect(resolution.target!.speakerId, 1);
    expect(resolution.target!.modelId, 'test-model');
  });

  test('emotionless dialogue with unknown speaker uses the narrator voice', () {
    final resolver = resolverWith(
      const TtsVoicePreferences(
        mode: TtsBackendKind.neural,
        narratorVoiceId: 'family:s1',
      ),
    );
    final resolution = resolver.resolve(role: SpeechRole.dialogue);
    expect(resolution.target?.speakerId, 1);
  });

  test('explicit per-resource binding wins over the default voice', () {
    final resolver = resolverWith(
      const TtsVoicePreferences(
        mode: TtsBackendKind.neural,
        narratorVoiceId: 'family:s1',
        defaultCharacterVoiceId: 'family:s2',
        bindingsByResourceId: <String, String>{'char-lin': 'family:s3'},
      ),
    );
    final resolution = resolver.resolve(
      role: SpeechRole.dialogue,
      speakerResourceId: 'char-lin',
    );
    expect(resolution.target?.speakerId, 3);
  });

  test('default character voice is used when there is no binding', () {
    final resolver = resolverWith(
      const TtsVoicePreferences(
        mode: TtsBackendKind.neural,
        defaultCharacterVoiceId: 'family:s2',
      ),
    );
    final resolution = resolver.resolve(
      role: SpeechRole.dialogue,
      speakerResourceId: 'unknown-char',
    );
    expect(resolution.target?.speakerId, 2);
  });

  test('auto assignment is deterministic and skips empty resource ids', () {
    final resolver = resolverWith(
      const TtsVoicePreferences(
        mode: TtsBackendKind.neural,
        autoAssignVoices: true,
      ),
    );
    resolver.beginSession(<String>['char-lin', 'char-chen']);
    final first = resolver.resolve(
      role: SpeechRole.dialogue,
      speakerResourceId: 'char-lin',
    );
    final second = resolver.resolve(
      role: SpeechRole.dialogue,
      speakerResourceId: 'char-lin',
    );
    expect(first.target?.voiceId, second.target?.voiceId);
    expect(first.target, isNotNull);
    // Unbound narration without a narrator voice is read by the system.
    expect(resolver.resolve(role: SpeechRole.narration).isSystem, isTrue);
  });

  test('an uninstalled model falls back instead of pretending to work', () {
    registry.installed = false;
    final resolver = resolverWith(
      const TtsVoicePreferences(
        mode: TtsBackendKind.neural,
        narratorVoiceId: 'family:s1',
      ),
    );
    final resolution = resolver.resolve(role: SpeechRole.narration);
    expect(resolution.fallback, isTrue);
    expect(resolution.target, isNull);
    expect(resolution.errorCode, TtsErrorCode.modelUnavailable);
  });

  group('compatible model priority', () {
    test('should prefer FP32 independently of catalog ordering', () {
      final models = TtsModelCatalog().models;
      for (final order in [models, models.reversed.toList()]) {
        final dualCatalog = TtsModelCatalog(models: order);
        final ids = models.map((m) => m.modelId).toSet();
        TtsModelDescriptor? resolved() =>
            dualCatalog.modelForVoice('kokoro-v1_1:s102',
                isInstalled: (m) => ids.contains(m.modelId));
        expect(resolved()?.modelId, 'kokoro-multi-lang-v1_1');
        ids.remove('kokoro-multi-lang-v1_1');
        expect(resolved()?.modelId, 'kokoro-int8-multi-lang-v1_1');
        ids.add('kokoro-multi-lang-v1_1');
        expect(resolved()?.modelId, 'kokoro-multi-lang-v1_1');
        ids.remove('kokoro-int8-multi-lang-v1_1');
        expect(resolved()?.modelId, 'kokoro-multi-lang-v1_1');
      }
    });
    test('should reject malformed and out of range voice ids', () {
      final defaults = TtsModelCatalog();
      for (final sid in ['-1', '103', '999', '0:s1', '1junk']) {
        expect(defaults.voiceById('kokoro-v1_1:s$sid'), isNull);
      }
      expect(defaults.voiceById('kokoro-v1_1:s0')?.speakerId, 0);
      expect(defaults.voiceById('kokoro-v1_1:s102')?.speakerId, 102);
    });
  });

  test('should reserve explicit voices during automatic collision avoidance',
      () {
    final resolver = resolverWith(const TtsVoicePreferences(
      mode: TtsBackendKind.neural,
      bindingsByResourceId: {'b': 'family:s0'},
    ));
    resolver.beginSession(['b', 'a']);
    expect(
        resolver
            .resolve(role: SpeechRole.dialogue, speakerResourceId: 'b')
            .target
            ?.voiceId,
        'family:s0');
    expect(
        resolver
            .resolve(role: SpeechRole.dialogue, speakerResourceId: 'a')
            .target
            ?.voiceId,
        isNot('family:s0'));
  });

  test('explicit system binding should override automatic assignment', () {
    final resolver = resolverWith(const TtsVoicePreferences(
      mode: TtsBackendKind.neural,
      narratorVoiceId: 'family:s1',
      defaultCharacterVoiceId: 'family:s2',
      bindingsByResourceId: {'character': 'system'},
    ));
    resolver.beginSession(['character']);
    final resolution = resolver.resolve(
        role: SpeechRole.dialogue, speakerResourceId: 'character');
    expect(resolution.isSystem, isTrue);
    expect(resolution.fallback, isFalse);
  });
}
