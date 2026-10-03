import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../domain/tts/tts_errors.dart';
import '../../domain/tts/tts_models.dart';
import 'tts_storage_error.dart';

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
    final archivePath = archive.path;
    final destinationPath = destinationDir.path;
    // Decompression and file-backed TAR writes are synchronous in archive.
    // A separate isolate keeps mobile/desktop UI responsive without buffering
    // the uncompressed model in memory.
    await Isolate.run(() async {
      try {
        await _extractOnWorker(
            File(archivePath), format, Directory(destinationPath));
      } on FileSystemException catch (error) {
        throw ttsFileSystemFailure(error, TtsErrorCode.modelInstallFailed);
      }
    });
  }

  Future<void> _extractOnWorker(
      File archive, TtsArchiveFormat format, Directory destinationDir) async {
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
      await _streamTarEntries(tarInput, root);
    } finally {
      tarInput.closeSync();
      if (await tarFile.exists()) await tarFile.delete();
    }
  }

  /// Reads TAR headers and copies file bodies in bounded chunks.
  ///
  /// `TarDecoder.decodeStream` materializes every entry when `storeData` is
  /// true, which turns a large neural model into a correspondingly large RAM
  /// spike. The installer only needs regular files/directories, so parsing the
  /// small 512-byte headers here keeps memory bounded by [_copyChunkSize].
  Future<void> _streamTarEntries(InputFileStream input, String root) async {
    String? pendingLongName;
    String? pendingPaxPath;
    var zeroBlocks = 0;
    try {
      while (!input.isEOS) {
        if (input.length < 512) {
          throw const TtsException(TtsErrorCode.modelArchiveInvalid,
              detail: 'truncated TAR header');
        }
        final header = input.readBytes(512).toUint8List();
        if (header.every((byte) => byte == 0)) {
          zeroBlocks++;
          if (zeroBlocks >= 2) break;
          continue;
        }
        zeroBlocks = 0;
        _verifyTarChecksum(header);

        final rawName = _tarString(header, 0, 100);
        final type = String.fromCharCode(header[156]);
        final size = _tarNumber(header, 124, 12);
        if (size < 0 || size > input.length) {
          throw const TtsException(TtsErrorCode.modelArchiveInvalid,
              detail: 'invalid TAR entry size');
        }

        if (type == 'L' || type == 'K') {
          final payload = await _readSmallEntry(input, size);
          final value =
              _decodeTarText(payload).replaceFirst(RegExp(r'\u0000+$'), '');
          if (type == 'L') {
            pendingLongName = value;
          } else {
            // GNU long link entries are never accepted as actual links. Read
            // and discard the metadata so the following entry remains aligned.
          }
          _skipTarPadding(input, size);
          continue;
        }
        if (type == 'x' || type == 'g') {
          final payload = await _readSmallEntry(input, size);
          final pax = _parsePax(payload);
          pendingPaxPath = pax['path'] ?? pendingPaxPath;
          _skipTarPadding(input, size);
          continue;
        }
        if (type != '0' && type != '\u0000' && type != '' && type != '5') {
          throw const TtsException(TtsErrorCode.modelArchiveInvalid,
              detail: 'non-regular TAR entry');
        }

        final name = pendingPaxPath ?? pendingLongName ?? rawName;
        pendingPaxPath = null;
        pendingLongName = null;
        final relative = _safeRelativePath(name);
        if (relative == null || relative == '.lt_extract.tar') {
          if (type == '5' && _isHarmlessRoot(name)) {
            _skipTarData(input, size);
            continue;
          }
          throw const TtsException(TtsErrorCode.modelArchiveInvalid,
              detail: 'unsafe entry');
        }
        final target = p.join(root, relative);
        _ensureWithinRoot(root, target);
        _rejectLinkAncestor(root, target);
        if (type == '5') {
          Directory(target).createSync(recursive: true);
          _skipTarData(input, size);
          continue;
        }

        Directory(p.dirname(target)).createSync(recursive: true);
        final output = OutputFileStream(target);
        try {
          var remaining = size;
          while (remaining > 0) {
            final count =
                remaining > _copyChunkSize ? _copyChunkSize : remaining;
            output.writeStream(input.readBytes(count));
            remaining -= count;
          }
          output.flush();
        } finally {
          output.closeSync();
        }
        _skipTarPadding(input, size);
      }
      if (zeroBlocks == 1) {
        throw const TtsException(TtsErrorCode.modelArchiveInvalid,
            detail: 'truncated TAR terminator');
      }
    } on ArchiveException catch (error) {
      throw TtsException(TtsErrorCode.modelArchiveInvalid, cause: error);
    }
  }

  static const int _copyChunkSize = 1024 * 1024;

  Future<Uint8List> _readSmallEntry(InputFileStream input, int size) async {
    if (size > 1024 * 1024) {
      throw const TtsException(TtsErrorCode.modelArchiveInvalid,
          detail: 'oversized TAR metadata');
    }
    return input.readBytes(size).toUint8List();
  }

  void _skipTarData(InputFileStream input, int size) {
    input.skip(size);
    _skipTarPadding(input, size);
  }

  void _skipTarPadding(InputFileStream input, int size) {
    final padding = (512 - (size % 512)) % 512;
    if (padding > input.length) {
      throw const TtsException(TtsErrorCode.modelArchiveInvalid,
          detail: 'truncated TAR entry');
    }
    input.skip(padding);
  }

  static String _tarString(Uint8List header, int offset, int length) {
    var end = offset;
    final limit = offset + length;
    while (end < limit && header[end] != 0) {
      end++;
    }
    return _decodeTarText(header.sublist(offset, end)).trim();
  }

  static int _tarNumber(Uint8List header, int offset, int length) {
    final raw = _tarString(header, offset, length).trim();
    if (raw.isEmpty) return 0;
    try {
      return int.parse(raw, radix: 8);
    } catch (_) {
      throw const TtsException(TtsErrorCode.modelArchiveInvalid,
          detail: 'invalid TAR number');
    }
  }

  static String _decodeTarText(Uint8List bytes) {
    final end = bytes.indexOf(0);
    final value = end < 0 ? bytes : bytes.sublist(0, end);
    return String.fromCharCodes(value);
  }

  static Map<String, String> _parsePax(Uint8List bytes) {
    final result = <String, String>{};
    var offset = 0;
    while (offset < bytes.length) {
      final space = bytes.indexOf(0x20, offset);
      if (space <= offset) {
        throw const TtsException(TtsErrorCode.modelArchiveInvalid,
            detail: 'invalid PAX header');
      }
      final length =
          int.tryParse(String.fromCharCodes(bytes.sublist(offset, space)));
      if (length == null ||
          length <= space - offset ||
          offset + length > bytes.length) {
        throw const TtsException(TtsErrorCode.modelArchiveInvalid,
            detail: 'invalid PAX length');
      }
      final record =
          String.fromCharCodes(bytes.sublist(offset, offset + length));
      final equals = record.indexOf('=');
      if (equals > space - offset && record.endsWith('\n')) {
        result[record.substring(space - offset + 1, equals)] =
            record.substring(equals + 1, record.length - 1);
      }
      offset += length;
    }
    return result;
  }

  static void _verifyTarChecksum(Uint8List header) {
    final expected = _tarNumber(header, 148, 8);
    var actual = 0;
    for (var i = 0; i < header.length; i++) {
      actual += (i >= 148 && i < 156) ? 0x20 : header[i];
    }
    if (actual != expected) {
      throw const TtsException(TtsErrorCode.modelArchiveInvalid,
          detail: 'invalid TAR checksum');
    }
  }

  static void _ensureWithinRoot(String root, String target) {
    if (!p.isWithin(root, target) && p.normalize(target) != root) {
      throw const TtsException(TtsErrorCode.modelArchiveInvalid,
          detail: 'path traversal');
    }
  }

  static void _rejectLinkAncestor(String root, String target) {
    var ancestor = target;
    while (ancestor != root) {
      if (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const TtsException(TtsErrorCode.modelArchiveInvalid,
            detail: 'filesystem link');
      }
      ancestor = p.dirname(ancestor);
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
      if (entry.isSymbolicLink) {
        throw const TtsException(TtsErrorCode.modelArchiveInvalid,
            detail: 'archive link');
      }
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
      if (relative == '.lt_extract.tar') {
        throw const TtsException(TtsErrorCode.modelArchiveInvalid);
      }
      final target = p.join(root, relative);
      var ancestor = target;
      while (ancestor != root) {
        if (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
            FileSystemEntityType.link) {
          throw const TtsException(TtsErrorCode.modelArchiveInvalid,
              detail: 'filesystem link');
        }
        ancestor = p.dirname(ancestor);
      }
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
    return name
        .replaceAll('\\', '/')
        .split('/')
        .every((part) => part.isEmpty || part == '.');
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
      if (segment == '..' ||
          segment.contains(':') ||
          segment.contains('\u0000')) {
        return null;
      }
      parts.add(segment);
    }
    if (parts.isEmpty) return null;
    return parts.join('/');
  }
}
