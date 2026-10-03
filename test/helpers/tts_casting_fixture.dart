import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/domain/tts/tts_voices.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_controller.dart';
import 'package:lt_dialogue/services/read_aloud/routed_read_aloud_engine.dart';
import 'package:lt_dialogue/services/tts/neural/neural_tts_engine.dart';
import 'package:lt_dialogue/services/tts/tts_model_catalog.dart';
import 'package:lt_dialogue/services/tts/tts_voice_binding_store.dart';
import 'package:lt_dialogue/services/tts/tts_voice_resolver.dart';

import 'read_aloud_fakes.dart';
import 'tts_fakes.dart';

/// Exercises the real planner, resolver, controller and routing boundaries.
/// Only native synthesis/audio and the install registry are replaced.
class TtsCastingFixture {
  TtsCastingFixture(
      {bool installed = true,
      bool autoRead = false,
      bool systemSupported = true}) {
    system = FakeReadAloudEngine(supported: systemSupported);
    registry = CastingModelRegistry(catalog.models, installed: installed);
    resolver = TtsVoiceResolver(
        catalog: catalog, bindings: bindings, registry: registry);
    routed = RoutedReadAloudEngine(
      systemEngine: system,
      neuralEngineFactory: () => neural,
      audioPlayerFactory: () => audio,
      neuralAvailable: () => registry.installed && bindings.isNeuralEnabled,
      modelPaths: (id) => NeuralTtsModelPaths(
          modelId: id,
          modelPath: '/fixture/model.onnx',
          voicesPath: '/fixture/voices.bin',
          tokensPath: '/fixture/tokens.txt',
          dataDirPath: '/fixture/data',
          lexicon: '',
          speakerCount: 103),
    );
    controller = ReadAloudController(
        engine: routed,
        voiceResolver: resolver,
        initialPreferences:
            ReadAloudPreferences(enabled: true, autoRead: autoRead));
  }

  final catalog = TtsModelCatalog();
  final bindings = TtsVoiceBindingStore(
      initial: const TtsVoicePreferences(
    mode: TtsBackendKind.neural,
    narratorVoiceId: 'kokoro-v1_1:s0',
    bindingsByResourceId: {'lin': 'kokoro-v1_1:s3', 'chen': 'kokoro-v1_1:s58'},
  ));
  late final FakeReadAloudEngine system;
  final neural = FakeNeuralTtsEngine();
  final audio = FakeNeuralAudioPlayer();
  late final CastingModelRegistry registry;
  late final TtsVoiceResolver resolver;
  late final RoutedReadAloudEngine routed;
  late final ReadAloudController controller;

  void dispose() {
    controller.dispose();
    bindings.dispose();
  }
}

class CastingModelRegistry implements TtsInstalledModelRegistry {
  CastingModelRegistry(this.models, {this.installed = true});
  final List<TtsModelDescriptor> models;
  bool installed;

  @override
  bool isModelInstalled(String id) =>
      installed && models.any((m) => m.modelId == id);

  @override
  List<TtsModelDescriptor> get installedModelDescriptors =>
      installed ? models : [];
}
