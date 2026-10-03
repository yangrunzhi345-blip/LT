import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../domain/tts/tts_errors.dart';
import '../../domain/tts/tts_models.dart';

/// Extracts a downloaded model archive into a staging directory.
///
/// Abstracted so the model manager can be tested without large archives.
abstract class TtsArchiveExtractor {
  /// Extracts [archive] into [destinationDir].
  ///
  /// Must reject unsafe entries (`../`, absolute paths, drive letters) with a
  /// [TtsException] carrying [TtsErrorCode.modelArchiveInvalid]. Callers own
  /// cleaning up the staging directory on failure.
  Future<void> extract({
    required File archive,
    required TtsArchiveFormat format,
    required Directory destinationDir,
  });
}

/// `package:archive` based extractor with strict path-traversal protection.
///
/// The archive is first decompressed to a temporary `.tar` on disk (bounded
/// memory), then each entry is validated and streamed to disk. Entries are
/// never executed; only data files are written.
class ArchiveTtsArchiveExtractor implements TtsArchiveExtractor {
  const ArchiveTtsArchiveExtractor();

  @override
  Future<void> extract({
    required File archive,
    required TtsArchiveFormat format,
    required Directory destinationDir,
  }) async {
    if (!await destinationDir.exists()) {
      await destinationDir.create(recursive: true);
    }
    final root = p.canonicalize(destinationDir.path);

    switch (format) {
      case TtsArchiveFormat.tarBz2:
        await _extractTar(archive, root, bzip2: true);
      case TtsArchiveFormat.tarGz:
        await _extractTar(archive, root, bzip2: false);
      case TtsArchiveFormat.zip:
        await _extractZip(archive, root);
    }
  }

  Future<void> _extractTar(
    File archive,
    String root, {
    required bool bzip2,
  }) async {
    final tarFile = File(p.join(root, '.lt_extract.tar'));
    final input = InputFileStream(archive.path);
    final output = OutputFileStream(tarFile.path);
    bool decoded;
    try {
      decoded = bzip2
          ? BZip2Decoder().decodeStream(input, output, verify: true)
          : const GZipDecoder().decodeStream(input, output, verify: true);
    } on ArchiveException catch (error) {
      throw TtsException(
        TtsErrorCode.modelArchiveInvalid,
        cause: error,
      );
    } finally {
      output.closeSync();
      input.closeSync();
    }
    if (!decoded) {
      throw const TtsException(
        TtsErrorCode.modelArchiveInvalid,
        detail: 'decompress failed',
      );
    }

    final tarInput = InputFileStream(tarFile.path);
    try {
      final Archive archiveData;
      try {
        // `storeData` must stay at its default (true): with `storeData: false`
        // the decoder yields `ArchiveFile.noData` entries whose content is
        // empty, so `writeContent` would silently produce 0-byte files. The
        // content is a file-backed stream, not buffered in memory.
        archiveData = TarDecoder().decodeStream(
          tarInput,
          verify: true,
        );
      } on ArchiveException catch (error) {
        throw TtsException(
          TtsErrorCode.modelArchiveInvalid,
          cause: error,
        );
      }
      _writeEntries(archiveData, root);
    } finally {
      tarInput.closeSync();
      if (await tarFile.exists()) await tarFile.delete();
    }
  }

  Future<void> _extractZip(File archive, String root) async {
    final input = InputFileStream(archive.path);
    try {
      final Archive archiveData;
      try {
        archiveData = ZipDecoder().decodeStream(input, verify: true);
      } on ArchiveException catch (error) {
        throw TtsException(TtsErrorCode.modelArchiveInvalid, cause: error);
      }
      _writeEntries(archiveData, root);
    } finally {
      input.closeSync();
    }
  }

  void _writeEntries(Archive archiveData, String root) {
    for (final entry in archiveData) {
      final relative = _safeRelativePath(entry.name);
      if (relative == null) {
        // A directory entry named `./` is harmless; anything with traversal or
        // absolute components is a hard failure.
        if (entry.isDirectory && _isHarmlessRoot(entry.name)) continue;
        throw const TtsException(
          TtsErrorCode.modelArchiveInvalid,
          detail: 'unsafe entry',
        );
      }
      final target = p.join(root, relative);
      if (!p.isWithin(root, target) && p.normalize(target) != root) {
        throw const TtsException(
          TtsErrorCode.modelArchiveInvalid,
          detail: 'path traversal',
        );
      }
      if (entry.isDirectory) {
        Directory(target).createSync(recursive: true);
        continue;
      }
      Directory(p.dirname(target)).createSync(recursive: true);
      final out = OutputFileStream(target);
      try {
        entry.writeContent(out);
      } finally {
        out.closeSync();
      }
    }
  }

  static bool _isHarmlessRoot(String name) {
    final normalized = name.replaceAll('\\', '/').replaceAll('.', '');
    return normalized.replaceAll('/', '').trim().isEmpty;
  }

  /// Normalizes [name] to a safe relative path, or returns null when the entry
  /// is absolute, uses a drive letter, or traverses with `..`.
  static String? _safeRelativePath(String name) {
    var value = name.replaceAll('\\', '/');
    if (value.startsWith('/')) return null;
    if (RegExp(r'^[a-zA-Z]:').hasMatch(value)) return null;
    final parts = <String>[];
    for (final segment in value.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') return null;
      parts.add(segment);
    }
    if (parts.isEmpty) return null;
    return parts.join('/');
  }
}
