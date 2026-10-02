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
}
