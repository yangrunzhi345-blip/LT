import 'dart:io';
import 'dart:convert';

import 'package:lt_dialogue/domain/tts/tts_errors.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/services/read_aloud/text_segmenter.dart';
import 'package:lt_dialogue/services/tts/neural/neural_tts_engine.dart';
import 'package:lt_dialogue/services/tts/neural/sherpa_neural_tts_engine.dart';
import 'package:lt_dialogue/services/tts/tts_archive_extractor.dart';
import 'package:lt_dialogue/services/tts/tts_download_client.dart';
import 'package:lt_dialogue/services/tts/tts_model_catalog.dart';
import 'package:lt_dialogue/services/tts/tts_model_manager.dart';
import 'package:lt_dialogue/services/tts/tts_model_storage.dart';
import 'package:path/path.dart' as p;

/// Explicit opt-in production validation; preserves the isolated model root.
/// No HTTP is issued unless [allowDownload] is true and no valid install exists.
Future<Map<String, Object?>> validateRealTtsModel({
  required Directory root,
  required bool allowDownload,
  Future<void> Function(String label, NeuralSynthesisResult result)? play,
}) async {
  final catalog = TtsModelCatalog();
  final descriptor = catalog.byId('kokoro-int8-multi-lang-v1_1')!;
  final storage = TtsModelStorage(rootProvider: () async => root);
  final manager = TtsModelManager(
    catalog: catalog,
    storage: storage,
    downloadClient: HttpTtsDownloadClient(),
    extractor: const ArchiveTtsArchiveExtractor(),
  );
  final engine = SherpaOnnxNeuralTtsEngine();
  final report = <String, Object?>{
    'model': descriptor.modelId,
    'downloadUri': descriptor.downloadUri.toString(),
    'archiveSize': descriptor.downloadSizeBytes,
    'archiveSha256': descriptor.integrity.digest,
    'license': descriptor.license,
    'audioPlayback': play == null ? 'NOT RUN' : 'pending',
  };
  void require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  try {
    await manager.initialize();
    final reused = manager.isModelInstalled(descriptor.modelId);
    if (!reused) {
      require(allowDownload,
          'No verified model; explicit download opt-in required');
      final installWatch = Stopwatch()..start();
      await manager.download(descriptor.modelId);
      report['installMilliseconds'] = installWatch.elapsedMilliseconds;
    }
    report['reused'] = reused;
    require(
        manager.statusOf(descriptor.modelId).state ==
            TtsModelInstallState.installed,
        'Production model installation failed: ${manager.statusOf(descriptor.modelId).errorCode}');
    final model = manager.installed(descriptor.modelId)!;
    final manifest = TtsInstalledManifest.fromJsonString(
        await (await storage.manifestFile(descriptor)).readAsString());
    require(manifest != null && manifest.fileSizes.isNotEmpty,
        'Missing verified file-size manifest');
    require(
        manifest!.modelId == descriptor.modelId &&
            manifest.integrityDigest == descriptor.integrity.digest &&
            manifest.speakerCount == 103,
        'Manifest identity mismatch');
    for (final entry in manifest.fileSizes.entries) {
      require(
          await File(p.join(model.rootPath, entry.key)).length() == entry.value,
          'File-size mismatch: ${entry.key}');
    }
    for (final file in [
      model.modelPath,
      model.voicesPath,
      model.tokensPath,
      ...model.lexiconFileNames.map((name) => p.join(model.rootPath, name))
    ]) {
      require(await File(file).length() > 0, 'Zero-byte required file');
    }
    require(
        await Directory(model.dataDirPath)
            .list(recursive: true)
            .any((entry) => entry is File),
        'Empty espeak data');
    report['installedBytes'] = manager.installedBytesFor(descriptor.modelId);
    report['requiredFileSizes'] = {
      for (final file in [
        model.modelPath,
        model.voicesPath,
        model.tokensPath,
        ...model.lexiconFileNames.map((name) => p.join(model.rootPath, name))
      ])
        p.basename(file): await File(file).length(),
    };
    report['rssBeforeLoad'] = ProcessInfo.currentRss;
    final loadWatch = Stopwatch()..start();
    final paths = NeuralTtsModelPaths(
      modelId: descriptor.modelId,
      modelPath: model.modelPath,
      voicesPath: model.voicesPath,
      tokensPath: model.tokensPath,
      dataDirPath: model.dataDirPath,
      lexicon: model.lexiconArgument,
      speakerCount: descriptor.speakerCount,
    );
    await engine.loadModel(paths);
    report['loadMilliseconds'] = loadWatch.elapsedMilliseconds;
    report['rssAfterLoad'] = ProcessInfo.currentRss;
    require(engine.isInitialized && engine.loadedModelId == descriptor.modelId,
        'Production model did not load');
    final cases = <({String label, String text, int sid})>[
      (label: 'narrator', text: '夜色降临，故事从这里开始。', sid: 3),
      (label: 'speaker-a', text: 'The story begins under the moon.', sid: 0),
      (label: 'speaker-b', text: 'The story begins under the moon.', sid: 102),
      (label: 'mixed', text: '你好，welcome to the story，故事开始了。', sid: 102),
    ];
    final results = <String, NeuralSynthesisResult>{};
    final metrics = <String, Object?>{};
    for (final item in cases) {
      final watch = Stopwatch()..start();
      final result =
          await engine.synthesize(text: item.text, speakerId: item.sid);
      watch.stop();
      require(!result.isEmpty && result.sampleRate == 24000,
          '${item.label} failed to generate 24 kHz PCM');
      require(
          result.samples
                  .every((sample) => sample.isFinite && sample.abs() <= 1) &&
              result.samples.any((sample) => sample.abs() > 0.0001),
          '${item.label} PCM invalid or silent');
      results[item.label] = result;
      final duration = result.samples.length / result.sampleRate;
      metrics[item.label] = {
        'sid': item.sid,
        'samples': result.samples.length,
        'sampleRate': result.sampleRate,
        'durationSeconds': duration,
        'inferenceMilliseconds': watch.elapsedMilliseconds,
        'rtf': watch.elapsedMicroseconds / 1000000 / duration,
      };
      if (play != null && item.label != 'mixed') await play(item.label, result);
    }
    final a = results['speaker-a']!.samples;
    final b = results['speaker-b']!.samples;
    var distinct = a.length != b.length;
    for (var index = 0; !distinct && index < a.length; index++) {
      distinct = a[index] != b[index];
    }
    require(distinct, 'Two different speaker IDs produced identical PCM');
    for (final invalidSid in [-1, 103, 999]) {
      var rejected = false;
      try {
        await engine.synthesize(
            text: 'Speaker bound check.', speakerId: invalidSid);
      } on TtsException {
        rejected = true;
      }
      require(rejected, 'Invalid speaker $invalidSid was not rejected');
    }
    report['invalidSpeakersRejected'] = [-1, 103, 999];
    const sentence = '月光照亮了安静的森林，旅人继续向前走，远处的城门逐渐出现在眼前。';
    final paragraph = List.filled(5, sentence).join();
    final chunks = const TextSegmenter().segment(paragraph);
    require(
        paragraph.length > 140 &&
            chunks.length > 1 &&
            chunks.every((chunk) => chunk.length <= 140),
        'Production long paragraph segmentation exceeded 140 units');
    require(
        chunks.join().replaceAll(RegExp(r'\s+'), '') ==
            paragraph.replaceAll(RegExp(r'\s+'), ''),
        'Segmentation lost content');
    final paragraphMetrics = <Object?>[];
    for (final chunk in chunks) {
      final watch = Stopwatch()..start();
      final result = await engine.synthesize(text: chunk, speakerId: 3);
      require(!result.isEmpty && result.sampleRate == 24000,
          'Long paragraph chunk failed synthesis');
      paragraphMetrics.add({
        'utf16Units': chunk.length,
        'samples': result.samples.length,
        'inferenceMilliseconds': watch.elapsedMilliseconds,
      });
    }
    report['longParagraph'] = {
      'utf16Units': paragraph.length,
      'maxChunkUnits': 140,
      'chunks': paragraphMetrics
    };
    report['synthesis'] = metrics;
    report['rssAfterSynthesis'] = ProcessInfo.currentRss;
    report['maxRss'] = ProcessInfo.maxRss;
    await engine.dispose();
    final cycles = <Object?>[];
    for (var index = 0; index < 3; index++) {
      final cycleEngine = SherpaOnnxNeuralTtsEngine();
      final before = ProcessInfo.currentRss;
      final watch = Stopwatch()..start();
      try {
        await cycleEngine.loadModel(paths);
        final afterLoad = ProcessInfo.currentRss;
        final result =
            await cycleEngine.synthesize(text: 'Hello.', speakerId: 0);
        require(!result.isEmpty, 'Reload cycle $index failed synthesis');
        await cycleEngine.dispose();
        cycles.add({
          'cycle': index + 1,
          'rssBefore': before,
          'rssAfterLoad': afterLoad,
          'rssAfterDispose': ProcessInfo.currentRss,
          'milliseconds': watch.elapsedMilliseconds
        });
      } finally {
        await cycleEngine.dispose();
      }
    }
    report['disposeReloadCycles'] = cycles;
    report['modelLoad'] = 'MODEL LOAD VERIFIED';
    report['generation'] = 'NEURAL GENERATION VERIFIED';
    report['multiSpeaker'] = 'MULTI-SPEAKER VERIFIED';
    if (play != null) report['audioPlayback'] = 'AUDIO PLAYBACK VERIFIED';
    return report;
  } finally {
    await engine.dispose();
    manager.dispose();
    report['rssAfterDispose'] = ProcessInfo.currentRss;
    await root.create(recursive: true);
    await File(p.join(root.path, 'validation-report.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true);
  }
}
