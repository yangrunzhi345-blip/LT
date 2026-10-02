import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/digests/sha256.dart';

import '../../domain/tts/tts_errors.dart';
import '../../domain/tts/tts_models.dart';
import 'tts_archive_extractor.dart';
import 'tts_download_client.dart';
import 'tts_model_catalog.dart';
import 'tts_model_storage.dart';
import 'tts_voice_resolver.dart';

/// A fully installed, on-disk model with resolved runtime paths.
class InstalledTtsModel {
  const InstalledTtsModel({
    required this.descriptor,
    required this.rootPath,
    required this.modelFileName,
    required this.lexiconFileNames,
  });

  final TtsModelDescriptor descriptor;
  final String rootPath;
  final String modelFileName;
  final List<String> lexiconFileNames;

  String get modelPath => p.join(rootPath, modelFileName);
  String get voicesPath => p.join(rootPath, 'voices.bin');
  String get tokensPath => p.join(rootPath, 'tokens.txt');
  String get dataDirPath => p.join(rootPath, 'espeak-ng-data');

  /// Comma-separated lexicon argument for sherpa-onnx.
  String get lexiconArgument =>
      lexiconFileNames.map((name) => p.join(rootPath, name)).join(',');
}

/// The single authority for neural TTS model installation.
///
/// It owns the catalog, download, verification, extraction, installation,
/// deletion and disk usage. It NEVER controls playback, and it NEVER downloads
/// anything on its own: a network request is only ever made when the user
/// explicitly calls [download].
class TtsModelManager extends ChangeNotifier
    implements TtsInstalledModelRegistry {
  TtsModelManager({
    required TtsModelCatalog catalog,
    required TtsModelStorage storage,
    required TtsDownloadClient downloadClient,
    required TtsArchiveExtractor extractor,
    DateTime Function()? clock,
  })  : _catalog = catalog,
        _storage = storage,
        _downloadClient = downloadClient,
        _extractor = extractor,
        _clock = clock ?? DateTime.now;

  final TtsModelCatalog _catalog;
  final TtsModelStorage _storage;
  final TtsDownloadClient _downloadClient;
  final TtsArchiveExtractor _extractor;
  final DateTime Function() _clock;

  final Map<String, TtsModelInstallStatus> _statuses =
      <String, TtsModelInstallStatus>{};
  final Map<String, bool> _cancelFlags = <String, bool>{};
  final Set<String> _running = <String>{};
  final Map<String, InstalledTtsModel> _installed =
      <String, InstalledTtsModel>{};
  final Map<String, int> _installedSizes = <String, int>{};

  bool _disposed = false;
  Future<void>? _initFuture;
  int _installedBytes = 0;

  TtsModelCatalog get catalog => _catalog;

  List<TtsModelInstallStatus> get statuses => _catalog.models
      .map((model) => statusOf(model.modelId))
      .toList(growable: false);

  List<InstalledTtsModel> get installedModels =>
      List.unmodifiable(_installed.values);

  int get installedBytes => _installedBytes;

  TtsModelInstallStatus statusOf(String modelId) =>
      _statuses[modelId] ?? TtsModelInstallStatus.notInstalled(modelId);

  InstalledTtsModel? installed(String modelId) => _installed[modelId];

  /// Measured on-disk size of an installed model, or 0 when not installed.
  int installedBytesFor(String modelId) => _installedSizes[modelId] ?? 0;

  @override
  bool isModelInstalled(String modelId) => _installed.containsKey(modelId);

  @override
  List<TtsModelDescriptor> get installedModelDescriptors => _installed.values
      .map((model) => model.descriptor)
      .toList(growable: false);

  /// Whether the voice is backed by an installed, verified model.
  bool isVoiceAvailable(String voiceId) {
    final model = _catalog.modelForVoice(
      voiceId,
      isInstalled: (candidate) => _installed.containsKey(candidate.modelId),
    );
    if (model == null) return false;
    return _installed.containsKey(model.modelId);
  }

  /// Scans disk state. Performs no network access. Idempotent.
  Future<void> initialize() {
    final active = _initFuture;
    if (active != null) return active;
    late final Future<void> future;
    future = refresh().whenComplete(() {
      if (identical(_initFuture, future)) _initFuture = null;
    });
    _initFuture = future;
    return future;
  }

  Future<void> refresh() async {
    final installed = <String, InstalledTtsModel>{};
    final sizes = <String, int>{};
    var bytes = 0;
    for (final model in _catalog.models) {
      final dir = await _storage.modelDir(model);
      final manifest = await _readManifest(model);
      final resolved = manifest == null
          ? null
          : await _resolveInstalled(model, dir, manifest);
      if (resolved != null) {
        installed[model.modelId] = resolved;
        final modelBytes = await _directorySize(dir);
        sizes[model.modelId] = modelBytes;
        bytes += modelBytes;
        _statuses[model.modelId] = TtsModelInstallStatus(
          modelId: model.modelId,
          state: TtsModelInstallState.installed,
          downloadedBytes: model.downloadSizeBytes,
          totalBytes: model.downloadSizeBytes,
        );
        continue;
      }

      final part = await _storage.partFile(model);
      if (await part.exists()) {
        final length = await part.length();
        _statuses[model.modelId] = TtsModelInstallStatus(
          modelId: model.modelId,
          state: TtsModelInstallState.paused,
          downloadedBytes: length,
          totalBytes: model.downloadSizeBytes,
        );
      } else {
        _statuses[model.modelId] =
            TtsModelInstallStatus.notInstalled(model.modelId);
      }
    }
    _installed
      ..clear()
      ..addAll(installed);
    _installedSizes
      ..clear()
      ..addAll(sizes);
    _installedBytes = bytes;
    _emit();
  }

  /// Explicit user action: download and install [modelId].
  Future<void> download(String modelId) async {
    if (_disposed || _running.contains(modelId)) return;
    final model = _catalog.byId(modelId);
    if (model == null) {
      throw const TtsException(TtsErrorCode.modelUnavailable);
    }
    _cancelFlags[modelId] = false;
    _running.add(modelId);
    _setStatus(
      TtsModelInstallStatus(
        modelId: modelId,
        state: TtsModelInstallState.downloading,
        downloadedBytes: statusOf(modelId).downloadedBytes,
        totalBytes: model.downloadSizeBytes,
      ),
    );
    try {
      await _install(model);
    } on TtsException catch (error) {
      _handleFailure(model, error);
    } catch (error) {
      _handleFailure(
        model,
        TtsException(TtsErrorCode.modelInstallFailed, cause: error),
      );
    } finally {
      _running.remove(modelId);
      _cancelFlags.remove(modelId);
    }
  }

  /// Pauses an in-flight download, preserving the `.part` file for resume.
  Future<void> pause(String modelId) async {
    if (!_running.contains(modelId)) return;
    _cancelFlags[modelId] = true;
    // The download loop observes the flag and stops on the next chunk.
  }

  /// Cancels a download and removes the partial file.
  Future<void> cancel(String modelId) async {
    _cancelFlags[modelId] = true;
    final model = _catalog.byId(modelId);
    if (model == null) return;
    final part = await _storage.partFile(model);
    if (await part.exists()) await part.delete();
    if (!_running.contains(modelId)) {
      _setStatus(TtsModelInstallStatus.notInstalled(modelId));
    }
  }

  /// Deletes an installed model. Voice bindings are intentionally preserved.
  Future<void> delete(String modelId) async {
    final model = _catalog.byId(modelId);
    if (model == null) return;
    _cancelFlags[modelId] = true;
    final dir = await _storage.modelDir(model);
    if (await dir.exists()) {
      _installedBytes -= _installedSizes[modelId] ?? await _directorySize(dir);
      await dir.delete(recursive: true);
    }
    final part = await _storage.partFile(model);
    if (await part.exists()) await part.delete();
    _installed.remove(modelId);
    _installedSizes.remove(modelId);
    _setStatus(TtsModelInstallStatus.notInstalled(modelId));
  }

  // ───────────────────────── install pipeline ─────────────────────────

  Future<void> _install(TtsModelDescriptor model) async {
    final downloadsDir = await _storage.downloadsDir();
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    final part = await _storage.partFile(model);

    final outcome = await _downloadClient.download(
      uri: model.downloadUri,
      destination: part,
      expectedTotalBytes: model.downloadSizeBytes,
      onProgress: (received, total) {
        if (_disposed) return;
        _setStatus(
          TtsModelInstallStatus(
            modelId: model.modelId,
            state: TtsModelInstallState.downloading,
            downloadedBytes: received,
            totalBytes: total,
          ),
        );
      },
      isCancelled: () => _cancelFlags[model.modelId] == true || _disposed,
    );

    if (_cancelFlags[model.modelId] == true) {
      // Pause: keep the partial file for resume.
      _setStatus(
        TtsModelInstallStatus(
          modelId: model.modelId,
          state: TtsModelInstallState.paused,
          downloadedBytes: outcome.bytesWritten,
          totalBytes: model.downloadSizeBytes,
        ),
      );
      return;
    }

    _setStatus(
      TtsModelInstallStatus(
        modelId: model.modelId,
        state: TtsModelInstallState.verifying,
        downloadedBytes: outcome.bytesWritten,
        totalBytes: model.downloadSizeBytes,
      ),
    );

    await _verify(model, part, outcome.bytesWritten);

    final staging = await _storage.newStagingDir(model);
    try {
      _setStatus(
        TtsModelInstallStatus(
          modelId: model.modelId,
          state: TtsModelInstallState.installing,
          downloadedBytes: outcome.bytesWritten,
          totalBytes: model.downloadSizeBytes,
        ),
      );
      await _extractor.extract(
        archive: part,
        format: model.archiveFormat,
        destinationDir: staging,
      );
      final root = await _locateModelRoot(staging, model);
      final modelFileName = await _locateModelFile(root, model);

      final modelDir = await _storage.modelDir(model);
      if (await modelDir.exists()) await modelDir.delete(recursive: true);
      await modelDir.parent.create(recursive: true);
      await _moveDirectory(root, modelDir);

      final manifest = TtsInstalledManifest.fromDescriptor(
        model,
        modelFileName: modelFileName,
        installedAt: _clock(),
      );
      final manifestFile = await _storage.manifestFile(model);
      await manifestFile.writeAsString(jsonEncode(manifest.toJson()));

      final resolved = InstalledTtsModel(
        descriptor: model,
        rootPath: modelDir.path,
        modelFileName: modelFileName,
        lexiconFileNames: _existingLexicons(modelDir.path, model),
      );
      _installed[model.modelId] = resolved;
      final installedBytes = await _directorySize(modelDir);
      _installedSizes[model.modelId] = installedBytes;
      _installedBytes += installedBytes;
      _setStatus(
        TtsModelInstallStatus(
          modelId: model.modelId,
          state: TtsModelInstallState.installed,
          downloadedBytes: model.downloadSizeBytes,
          totalBytes: model.downloadSizeBytes,
        ),
      );
    } on TtsException {
      rethrow;
    } catch (error) {
      throw TtsException(TtsErrorCode.modelInstallFailed, cause: error);
    } finally {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup; the original error is more useful.
      }
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  Future<void> _verify(
    TtsModelDescriptor model,
    File part,
    int downloadedBytes,
  ) async {
    if (downloadedBytes != model.downloadSizeBytes) {
      throw const TtsException(
        TtsErrorCode.modelIntegrityFailed,
        detail: 'size mismatch',
      );
    }
    final actual = await _sha256Of(part);
    final expected = model.integrity.digest.toLowerCase();
    if (actual != expected) {
      throw const TtsException(
        TtsErrorCode.modelIntegrityFailed,
        detail: 'digest mismatch',
      );
    }
  }

  Future<TtsInstalledManifest?> _readManifest(TtsModelDescriptor model) async {
    final file = await _storage.manifestFile(model);
    if (!await file.exists()) return null;
    try {
      return TtsInstalledManifest.fromJsonString(await file.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<InstalledTtsModel?> _resolveInstalled(
    TtsModelDescriptor model,
    Directory dir,
    TtsInstalledManifest manifest,
  ) async {
    if (!await dir.exists()) return null;
    if (manifest.modelId != model.modelId) return null;
    final modelPath = p.join(dir.path, manifest.modelFileName);
    if (!await File(modelPath).exists()) return null;
    for (final required in model.requiredFiles) {
      if (!await _entryExists(p.join(dir.path, required.name))) return null;
    }
    return InstalledTtsModel(
      descriptor: model,
      rootPath: dir.path,
      modelFileName: manifest.modelFileName,
      lexiconFileNames: manifest.lexiconFileNames.isEmpty
          ? _existingLexicons(dir.path, model)
          : manifest.lexiconFileNames,
    );
  }

  /// Locates the directory containing the model files after extraction.
  ///
  /// The official archives wrap everything in a single top-level directory, but
  /// we locate the model file by name instead of assuming the layout.
  Future<Directory> _locateModelRoot(
    Directory staging,
    TtsModelDescriptor model,
  ) async {
    final stack = <Directory>[staging];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      final children = await dir.list(followLinks: false).toList();
      for (final entity in children) {
        if (entity is! File) continue;
        if (model.modelFileName.contains(p.basename(entity.path))) {
          return dir;
        }
      }
      for (final entity in children) {
        if (entity is Directory) stack.add(entity);
      }
    }
    throw const TtsException(
      TtsErrorCode.modelInstallFailed,
      detail: 'model file missing',
    );
  }

  Future<String> _locateModelFile(
    Directory root,
    TtsModelDescriptor model,
  ) async {
    for (final candidate in model.modelFileName) {
      if (await File(p.join(root.path, candidate)).exists()) return candidate;
    }
    throw const TtsException(
      TtsErrorCode.modelInstallFailed,
      detail: 'model file missing',
    );
  }

  List<String> _existingLexicons(String root, TtsModelDescriptor model) {
    final result = <String>[];
    for (final name in model.lexiconFileNames) {
      if (File(p.join(root, name)).existsSync()) result.add(name);
    }
    return result;
  }

  Future<bool> _entryExists(String path) async {
    if (await File(path).exists()) return true;
    return Directory(path).exists();
  }

  Future<void> _moveDirectory(Directory from, Directory to) async {
    try {
      await from.rename(to.path);
    } on FileSystemException {
      // Cross-device fallback: copy then delete.
      await _copyDirectory(from, to);
      if (await from.exists()) await from.delete(recursive: true);
    }
  }

  Future<void> _copyDirectory(Directory from, Directory to) async {
    await to.create(recursive: true);
    await for (final entity in from.list(recursive: false)) {
      final name = p.basename(entity.path);
      final target = p.join(to.path, name);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }

  Future<int> _directorySize(Directory dir) async {
    var total = 0;
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // File vanished mid-scan; ignore.
        }
      }
    }
    return total;
  }

  Future<String> _sha256Of(File file) async {
    final digest = SHA256Digest();
    await for (final chunk in file.openRead()) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      digest.update(bytes, 0, bytes.length);
    }
    final out = Uint8List(digest.digestSize);
    digest.doFinal(out, 0);
    return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void _handleFailure(TtsModelDescriptor model, TtsException error) {
    if (_cancelFlags[model.modelId] == true) {
      _setStatus(
        TtsModelInstallStatus(
          modelId: model.modelId,
          state: TtsModelInstallState.paused,
          downloadedBytes: statusOf(model.modelId).downloadedBytes,
          totalBytes: model.downloadSizeBytes,
        ),
      );
      return;
    }
    _setStatus(
      TtsModelInstallStatus(
        modelId: model.modelId,
        state: TtsModelInstallState.failed,
        downloadedBytes: statusOf(model.modelId).downloadedBytes,
        totalBytes: model.downloadSizeBytes,
        errorCode: error.code,
      ),
    );
  }

  void _setStatus(TtsModelInstallStatus status) {
    if (_disposed) return;
    _statuses[status.modelId] = status;
    _emit();
  }

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_downloadClient.close());
    super.dispose();
  }
}
