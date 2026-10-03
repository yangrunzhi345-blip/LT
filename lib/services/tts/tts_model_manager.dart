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
import 'tts_storage_error.dart';
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
    this.beforeDelete,
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

  /// Releases an active runtime before removing its files. Playback stays owned
  /// by ReadAloudController and its delegated engine.
  final Future<void> Function(String modelId)? beforeDelete;

  final Map<String, TtsModelInstallStatus> _statuses =
      <String, TtsModelInstallStatus>{};
  final Map<String, bool> _cancelFlags = <String, bool>{};
  final Set<String> _running = <String>{};
  final Map<String, InstalledTtsModel> _installed =
      <String, InstalledTtsModel>{};
  final Map<String, int> _installedSizes = <String, int>{};

  final Map<String, Future<void>> _tasks = {};
  final Map<String, Future<void>> _deletions = {};
  final Map<String, Future<void>> _cancellations = {};
  final Set<String> _removePartial = {};
  final Map<String, int> _revisions = {};
  Future<void>? _refreshFuture;
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

  InstalledTtsModel? installed(String modelId) =>
      isModelInstalled(modelId) ? _installed[modelId] : null;

  /// Measured on-disk size of an installed model, or 0 when not installed.
  int installedBytesFor(String modelId) => _installedSizes[modelId] ?? 0;

  @override
  bool isModelInstalled(String modelId) =>
      !_deletions.containsKey(modelId) && _installed.containsKey(modelId);

  @override
  List<TtsModelDescriptor> get installedModelDescriptors => _installed.values
      .where((model) => isModelInstalled(model.descriptor.modelId))
      .map((model) => model.descriptor)
      .toList(growable: false);

  /// Whether the voice is backed by an installed, verified model.
  bool isVoiceAvailable(String voiceId) {
    final model = _catalog.modelForVoice(
      voiceId,
      isInstalled: (candidate) => isModelInstalled(candidate.modelId),
    );
    if (model == null) return false;
    return isModelInstalled(model.modelId);
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

  Future<void> refresh() => _refreshFuture ??= _refresh().whenComplete(() {
        _refreshFuture = null;
      });

  Future<void> _refresh() async {
    for (final model in _catalog.models) {
      final id = model.modelId;
      if (_running.contains(id) ||
          _deletions.containsKey(id) ||
          _cancellations.containsKey(id)) {
        continue;
      }
      final revision = _revisions[id] ?? 0;
      final dir = await _storage.modelDir(model);
      final manifest = await _readManifest(model);
      InstalledTtsModel? resolved;
      try {
        resolved = manifest == null
            ? null
            : await _resolveInstalled(model, dir, manifest);
      } on FileSystemException {
        resolved = null;
      } on TtsException {
        resolved = null;
      }
      final size = resolved == null ? 0 : await _directorySize(dir);
      final part = await _storage.partFile(model);
      final partSize = await part.exists() ? await part.length() : 0;
      if (_disposed ||
          _running.contains(id) ||
          _deletions.containsKey(id) ||
          _cancellations.containsKey(id) ||
          revision != (_revisions[id] ?? 0)) {
        continue;
      }
      if (resolved != null) {
        _installed[id] = resolved;
        _installedSizes[id] = size;
        _statuses[id] = TtsModelInstallStatus(
            modelId: id,
            state: TtsModelInstallState.installed,
            downloadedBytes: model.downloadSizeBytes,
            totalBytes: model.downloadSizeBytes);
        if (partSize > 0) {
          // A crash after atomic publication can leave its verified archive.
          // Register cleanup before yielding so a new download/delete waits.
          final cleanup = Future<void>.microtask(() async {
            if (await part.exists()) await part.delete();
          }).whenComplete(() {
            _cancellations.remove(id);
          });
          _cancellations[id] = cleanup;
          await cleanup;
        }
      } else {
        _installed.remove(id);
        _installedSizes.remove(id);
        _statuses[id] = partSize > 0
            ? TtsModelInstallStatus(
                modelId: id,
                state: TtsModelInstallState.paused,
                downloadedBytes: partSize,
                totalBytes: model.downloadSizeBytes)
            : TtsModelInstallStatus.notInstalled(id);
      }
    }
    // Only known staging directories with no live owner are crash leftovers.
    final staging = await _storage.stagingDir();
    if (await staging.exists()) {
      await for (final entry in staging.list(followLinks: false)) {
        if (entry is! Directory) continue;
        for (final model in _catalog.models) {
          if (p
                  .basename(entry.path)
                  .startsWith('${model.modelId}.${model.version}.') &&
              !_running.contains(model.modelId)) {
            await entry.delete(recursive: true);
            break;
          }
        }
      }
    }
    _recountBytes();
    _emit();
  }

  /// Explicit user action. Duplicate clicks are ignored; a cancelled operation
  /// finishes closing/cleaning its own files before a retry starts.
  Future<void> download(String modelId) async {
    if (_disposed) return;
    final deletion = _deletions[modelId];
    if (deletion != null) await deletion;
    final cancellation = _cancellations[modelId];
    if (cancellation != null) await cancellation;
    final task = _tasks[modelId];
    if (task != null) {
      if (_cancelFlags[modelId] != true) return;
      await task;
      return download(modelId);
    }
    final model = _catalog.byId(modelId);
    if (model == null) throw const TtsException(TtsErrorCode.modelUnavailable);
    if (isModelInstalled(modelId)) return;
    _cancelFlags[modelId] = false;
    _running.add(modelId);
    _revisions[modelId] = (_revisions[modelId] ?? 0) + 1;
    // Register ownership before emitting the first status, so a listener can
    // cancel synchronously without observing a writer with no task handle.
    final future = Future<void>.microtask(() => _runDownload(model));
    _tasks[modelId] = future;
    await future;
  }

  Future<void> _runDownload(TtsModelDescriptor model) async {
    final id = model.modelId;
    try {
      _setStatus(TtsModelInstallStatus(
          modelId: id,
          state: TtsModelInstallState.downloading,
          downloadedBytes: statusOf(id).downloadedBytes,
          totalBytes: model.downloadSizeBytes));
      await _install(model);
    } on TtsException catch (error) {
      if (error.code == TtsErrorCode.modelIntegrityFailed) {
        final part = await _storage.partFile(model);
        if (await part.exists()) await part.delete();
      }
      _handleFailure(model, error);
    } catch (error) {
      _handleFailure(
          model, ttsFileSystemFailure(error, TtsErrorCode.modelInstallFailed));
    } finally {
      try {
        if (_removePartial.contains(id)) {
          final part = await _storage.partFile(model);
          if (await part.exists()) await part.delete();
          _setStatus(TtsModelInstallStatus.notInstalled(id));
        }
      } finally {
        _running.remove(id);
        _tasks.remove(id);
        _cancelFlags.remove(id);
        _removePartial.remove(id);
        _revisions[id] = (_revisions[id] ?? 0) + 1;
      }
    }
  }

  Future<void> _interrupt(String id, {required bool removePartial}) async {
    if (!_running.contains(id)) return;
    // Atomic publication is the commit point. Cancellation after that point
    // waits for final accounting rather than reverting only the status mirror.
    if (_installed.containsKey(id)) {
      await _tasks[id];
      return;
    }
    _cancelFlags[id] = true;
    if (removePartial) _removePartial.add(id);
    final task = _tasks[id];
    final model = _catalog.byId(id);
    if (model != null) {
      final part = await _storage.partFile(model);
      if (identical(_tasks[id], task)) _downloadClient.cancel(part);
    }
    await task;
  }

  /// Pauses and waits for the writer to close, preserving resumable bytes.
  Future<void> pause(String modelId) =>
      _interrupt(modelId, removePartial: false);

  /// Cancels and waits for cleanup before a new operation can use the file.
  Future<void> cancel(String modelId) {
    final active = _cancellations[modelId];
    if (active != null) return active;
    final future = _cancel(modelId).whenComplete(() {
      _cancellations.remove(modelId);
    });
    _cancellations[modelId] = future;
    return future;
  }

  Future<void> _cancel(String modelId) async {
    if (_installed.containsKey(modelId)) {
      await _tasks[modelId];
      return;
    }
    if (_running.contains(modelId)) {
      await _interrupt(modelId, removePartial: true);
      return;
    }
    final model = _catalog.byId(modelId);
    if (model == null || _deletions.containsKey(modelId)) return;
    final part = await _storage.partFile(model);
    if (await part.exists()) await part.delete();
    if (!isModelInstalled(modelId)) {
      _setStatus(TtsModelInstallStatus.notInstalled(modelId));
    }
  }

  /// Stops/releases the model's active runtime, then deletes its files.
  /// Voice bindings belong to a separate authority and are preserved.
  Future<void> delete(String modelId) {
    final active = _deletions[modelId];
    if (active != null) return active;
    final future = _delete(modelId).whenComplete(() {
      _deletions.remove(modelId);
    });
    _deletions[modelId] = future;
    return future;
  }

  Future<void> _delete(String id) async {
    final model = _catalog.byId(id);
    if (model == null) return;
    _revisions[id] = (_revisions[id] ?? 0) + 1;
    await _cancellations[id];
    await _interrupt(id, removePartial: true);
    await beforeDelete?.call(id);
    final dir = await _storage.modelDir(model);
    if (await dir.exists()) await dir.delete(recursive: true);
    final part = await _storage.partFile(model);
    if (await part.exists()) await part.delete();
    _installed.remove(id);
    _installedSizes.remove(id);
    _recountBytes();
    _setStatus(TtsModelInstallStatus.notInstalled(id));
  }

  void _checkCancelled(TtsModelDescriptor model) {
    if (_disposed || _cancelFlags[model.modelId] == true) {
      throw const TtsException(TtsErrorCode.cancelled);
    }
  }

  void _recountBytes() {
    _installedBytes =
        _installedSizes.values.fold(0, (sum, value) => sum + value);
  }

  // ───────────────────────── install pipeline ─────────────────────────

  Future<void> _install(TtsModelDescriptor model) async {
    _checkCancelled(model);
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
        if (_disposed || _cancelFlags[model.modelId] == true) return;
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

    _checkCancelled(model);

    _setStatus(
      TtsModelInstallStatus(
        modelId: model.modelId,
        state: TtsModelInstallState.verifying,
        downloadedBytes: outcome.bytesWritten,
        totalBytes: model.downloadSizeBytes,
      ),
    );

    await _verify(model, part, outcome.bytesWritten);
    _checkCancelled(model);

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
      _checkCancelled(model);
      if (!await _validateTree(model, root, modelFileName)) {
        throw const TtsException(TtsErrorCode.modelIntegrityFailed,
            detail: 'incomplete or empty model files');
      }
      final fileSizes = await _fileSizes(root);
      final manifest = TtsInstalledManifest.fromDescriptor(model,
          modelFileName: modelFileName,
          installedAt: _clock(),
          fileSizes: fileSizes);
      // The manifest is part of the atomic directory publication. A crash can
      // leave a staging tree, never a published tree with a half-written manifest.
      await File(p.join(root.path, TtsInstalledManifest.fileName))
          .writeAsString(jsonEncode(manifest.toJson()), flush: true);
      _checkCancelled(model);

      final modelDir = await _storage.modelDir(model);
      if (await modelDir.exists()) await modelDir.delete(recursive: true);
      await modelDir.parent.create(recursive: true);
      _checkCancelled(model);
      await _moveDirectory(root, modelDir);
      if (_disposed || _cancelFlags[model.modelId] == true) {
        await modelDir.delete(recursive: true);
        throw const TtsException(TtsErrorCode.cancelled);
      }

      final resolved = InstalledTtsModel(
        descriptor: model,
        rootPath: modelDir.path,
        modelFileName: modelFileName,
        lexiconFileNames: _existingLexicons(modelDir.path, model),
      );
      _installed[model.modelId] = resolved;
      final installedBytes = await _directorySize(modelDir);
      _installedSizes[model.modelId] = installedBytes;
      _recountBytes();
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
      throw ttsFileSystemFailure(error, TtsErrorCode.modelInstallFailed);
    } finally {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup; the original error is more useful.
      }
      try {
        if (await part.exists() &&
            (_cancelFlags[model.modelId] != true ||
                _removePartial.contains(model.modelId))) {
          await part.delete();
        }
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
    if (manifest.modelId != model.modelId ||
        manifest.version != model.version ||
        manifest.voiceFamily != model.voiceFamily ||
        manifest.speakerCount != model.speakerCount ||
        manifest.integrityAlgorithm != model.integrity.algorithm ||
        manifest.integrityDigest != model.integrity.digest ||
        manifest.integritySource != model.integrity.source.name ||
        DateTime.tryParse(manifest.installedAt) == null ||
        !model.modelFileName.contains(manifest.modelFileName) ||
        !listEquals(manifest.lexiconFileNames, model.lexiconFileNames)) {
      return null;
    }
    if (!await _validateTree(model, dir, manifest.modelFileName)) return null;
    if (manifest.fileSizes.isNotEmpty) {
      final actual = await _fileSizes(dir);
      if (!mapEquals(actual, manifest.fileSizes)) return null;
    }
    return InstalledTtsModel(
        descriptor: model,
        rootPath: dir.path,
        modelFileName: manifest.modelFileName,
        lexiconFileNames: model.lexiconFileNames);
  }

  Future<bool> _validateTree(
      TtsModelDescriptor model, Directory root, String modelFile) async {
    if (!await root.exists()) return false;
    for (final name in [modelFile, ...model.lexiconFileNames]) {
      final file = File(p.join(root.path, name));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() <= 0) {
        return false;
      }
    }
    for (final spec in model.requiredFiles) {
      final path = p.join(root.path, spec.name);
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        final size = await File(path).length();
        if (size <= 0 || (spec.sizeBytes != null && size != spec.sizeBytes)) {
          return false;
        }
      } else if (type == FileSystemEntityType.directory) {
        var nonempty = false;
        await for (final child
            in Directory(path).list(recursive: true, followLinks: false)) {
          if (child is Link) return false;
          if (child is File && await child.length() > 0) nonempty = true;
        }
        if (!nonempty) return false;
      } else {
        return false;
      }
    }
    return true;
  }

  Future<Map<String, int>> _fileSizes(Directory dir) async {
    final sizes = <String, int>{};
    await for (final entry in dir.list(recursive: true, followLinks: false)) {
      if (entry is Link) {
        throw const TtsException(TtsErrorCode.modelIntegrityFailed);
      }
      if (entry is File &&
          p.basename(entry.path) != TtsInstalledManifest.fileName) {
        sizes[p.relative(entry.path, from: dir.path).replaceAll('\\', '/')] =
            await entry.length();
      }
    }
    return sizes;
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

  Future<void> _moveDirectory(Directory from, Directory to) async {
    // Both live under the same app-support root. Copying on arbitrary rename
    // failures would expose a partial installation and hide Windows locks.
    await from.rename(to.path);
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
