import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../read_aloud/flutter_tts_engine.dart';
import '../read_aloud/read_aloud_engine.dart';
import '../read_aloud/routed_read_aloud_engine.dart';
import '../repositories/settings_repository.dart';
import 'neural/audio_players_neural_audio_player.dart';
import 'neural/neural_audio_player.dart';
import 'neural/neural_tts_engine.dart';
import 'neural/sherpa_neural_tts_engine.dart';
import 'tts_archive_extractor.dart';
import 'tts_download_client.dart';
import 'tts_model_catalog.dart';
import 'tts_model_manager.dart';
import 'tts_model_storage.dart';
import 'tts_voice_binding_store.dart';
import 'tts_voice_resolver.dart';

/// Composition root for the optional neural TTS stack.
///
/// Bundles the catalog, the single [TtsModelManager] install authority, the
/// device-local voice bindings, the voice resolver and the routed engine.
/// Building it performs no IO and no network; call [TtsModelManager.initialize]
/// to scan disk, and never anything else to trigger a download.
class TtsRuntime {
  TtsRuntime({
    required this.catalog,
    required this.manager,
    required this.bindings,
    required this.resolver,
    required this.engine,
  });

  factory TtsRuntime.production({
    required ISettingsRepository settingsRepo,
    Future<Directory> Function()? rootProvider,
    TtsModelCatalog? catalog,
    ReadAloudEngine Function()? systemEngineFactory,
    NeuralTtsEngine Function()? neuralEngineFactory,
    NeuralAudioPlayer Function()? audioPlayerFactory,
    TtsDownloadClient Function()? downloadClientFactory,
    TtsArchiveExtractor? extractor,
  }) {
    final resolvedCatalog = catalog ?? TtsModelCatalog();
    final storage = TtsModelStorage(
      rootProvider: rootProvider ?? getApplicationSupportDirectory,
    );
    final manager = TtsModelManager(
      catalog: resolvedCatalog,
      storage: storage,
      downloadClient: (downloadClientFactory ?? HttpTtsDownloadClient.new)(),
      extractor: extractor ?? const ArchiveTtsArchiveExtractor(),
    );
    final bindings = TtsVoiceBindingStore(
      store: SettingsRepoTtsVoiceStore(settingsRepo),
    );
    final resolver = TtsVoiceResolver(
      catalog: resolvedCatalog,
      bindings: bindings,
      registry: manager,
    );
    final engine = RoutedReadAloudEngine(
      systemEngine: (systemEngineFactory ?? createDefaultReadAloudEngine)(),
      neuralEngineFactory: neuralEngineFactory ?? SherpaOnnxNeuralTtsEngine.new,
      audioPlayerFactory:
          audioPlayerFactory ?? AudioPlayersNeuralAudioPlayer.new,
      modelPaths: (modelId) {
        final installed = manager.installed(modelId);
        if (installed == null) return null;
        return NeuralTtsModelPaths(
          modelId: modelId,
          modelPath: installed.modelPath,
          voicesPath: installed.voicesPath,
          tokensPath: installed.tokensPath,
          dataDirPath: installed.dataDirPath,
          lexicon: installed.lexiconArgument,
          speakerCount: installed.descriptor.speakerCount,
        );
      },
    );
    return TtsRuntime(
      catalog: resolvedCatalog,
      manager: manager,
      bindings: bindings,
      resolver: resolver,
      engine: engine,
    );
  }

  final TtsModelCatalog catalog;
  final TtsModelManager manager;
  final TtsVoiceBindingStore bindings;
  final TtsVoiceResolver resolver;
  final RoutedReadAloudEngine engine;

  bool _disposed = false;

  /// Scans installed models. Performs no network access.
  ///
  /// Failures (for example a missing platform directory plugin in a unit test)
  /// are logged and swallowed: they must never surface as an unhandled error or
  /// block the app. System TTS keeps working regardless.
  Future<void> initialize() async {
    try {
      await manager.initialize();
    } catch (error) {
      debugPrint('[TtsRuntime] 初始化模型状态失败: $error');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    manager.dispose();
    bindings.dispose();
  }
}
