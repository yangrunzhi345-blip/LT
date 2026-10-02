import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/tts/tts_models.dart';

/// Metadata written next to an installed model, used to detect corruption and
/// to build the sherpa-onnx runtime configuration.
class TtsInstalledManifest {
  const TtsInstalledManifest({
    required this.modelId,
    required this.version,
    required this.voiceFamily,
    required this.speakerCount,
    required this.modelFileName,
    required this.installedAt,
    required this.integrityAlgorithm,
    required this.integrityDigest,
    required this.integritySource,
    required this.lexiconFileNames,
  });

  final String modelId;
  final String version;
  final String voiceFamily;
  final int speakerCount;

  /// Relative file name of the ONNX model inside the model root.
  final String modelFileName;

  final String installedAt;
  final String integrityAlgorithm;
  final String integrityDigest;
  final String integritySource;
  final List<String> lexiconFileNames;

  static const String fileName = 'manifest.json';

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': 1,
        'modelId': modelId,
        'version': version,
        'voiceFamily': voiceFamily,
        'speakerCount': speakerCount,
        'modelFileName': modelFileName,
        'installedAt': installedAt,
        'integrity': <String, Object?>{
          'algorithm': integrityAlgorithm,
          'digest': integrityDigest,
          'source': integritySource,
        },
        'lexicon': lexiconFileNames,
      };

  static TtsInstalledManifest? fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final integrity = decoded['integrity'];
      final modelFileName = decoded['modelFileName'];
      final modelId = decoded['modelId'];
      final version = decoded['version'];
      if (modelId is! String ||
          version is! String ||
          modelFileName is! String ||
          integrity is! Map) {
        return null;
      }
      return TtsInstalledManifest(
        modelId: modelId,
        version: version,
        voiceFamily: decoded['voiceFamily'] as String? ?? '',
        speakerCount: (decoded['speakerCount'] as num?)?.toInt() ?? 0,
        modelFileName: modelFileName,
        installedAt: decoded['installedAt'] as String? ?? '',
        integrityAlgorithm: integrity['algorithm'] as String? ?? '',
        integrityDigest: integrity['digest'] as String? ?? '',
        integritySource: integrity['source'] as String? ?? '',
        lexiconFileNames: <String>[
          for (final item in (decoded['lexicon'] as List? ?? const <Object?>[]))
            if (item is String) item,
        ],
      );
    } catch (_) {
      return null;
    }
  }

  static TtsInstalledManifest fromDescriptor(
    TtsModelDescriptor descriptor, {
    required String modelFileName,
    required DateTime installedAt,
  }) {
    return TtsInstalledManifest(
      modelId: descriptor.modelId,
      version: descriptor.version,
      voiceFamily: descriptor.voiceFamily,
      speakerCount: descriptor.speakerCount,
      modelFileName: modelFileName,
      installedAt: installedAt.toUtc().toIso8601String(),
      integrityAlgorithm: descriptor.integrity.algorithm,
      integrityDigest: descriptor.integrity.digest,
      integritySource: descriptor.integrity.source.name,
      lexiconFileNames: descriptor.lexiconFileNames,
    );
  }
}

/// Resolves the on-disk layout for models, downloads and staging.
///
/// Everything lives under the writable application-support directory. Models
/// are never written to `assets/`, the source tree, the working directory or a
/// hard-coded user directory.
///
/// ```
/// <ApplicationSupport>/
///   tts/
///     models/<modelId>/<version>/{manifest.json,...}
///     downloads/<modelId>.<version>.part
///     staging/
/// ```
class TtsModelStorage {
  TtsModelStorage({required Future<Directory> Function() rootProvider})
      : _rootProvider = rootProvider;

  final Future<Directory> Function() _rootProvider;

  Future<Directory> _root() async {
    final base = await _rootProvider();
    final dir = Directory(p.join(base.path, 'tts'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> modelsDir() async =>
      Directory(p.join((await _root()).path, 'models'));

  Future<Directory> downloadsDir() async =>
      Directory(p.join((await _root()).path, 'downloads'));

  Future<Directory> stagingDir() async =>
      Directory(p.join((await _root()).path, 'staging'));

  Future<Directory> modelDir(TtsModelDescriptor model) async {
    final base = await modelsDir();
    return Directory(p.join(base.path, model.modelId, model.version));
  }

  Future<File> manifestFile(TtsModelDescriptor model) async =>
      File(p.join((await modelDir(model)).path, TtsInstalledManifest.fileName));

  /// Partial download file. Never treated as an installed model.
  Future<File> partFile(TtsModelDescriptor model) async {
    final base = await downloadsDir();
    return File(
      p.join(base.path, '${model.modelId}.${model.version}.part'),
    );
  }

  /// A fresh staging directory for one install attempt.
  Future<Directory> newStagingDir(TtsModelDescriptor model) async {
    final base = await stagingDir();
    if (!await base.exists()) await base.create(recursive: true);
    final unique = DateTime.now().microsecondsSinceEpoch;
    final dir = Directory(
      p.join(base.path, '${model.modelId}.${model.version}.$unique'),
    );
    await dir.create(recursive: true);
    return dir;
  }

  /// Allows tests and teardown code to redirect the root.
  Future<Directory> rootForTesting() => _root();
}
