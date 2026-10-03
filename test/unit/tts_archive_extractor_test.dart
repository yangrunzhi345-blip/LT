import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/tts/tts_errors.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/services/tts/tts_archive_extractor.dart';

void main() {
  const extractor = ArchiveTtsArchiveExtractor();
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lt_tts_archive_');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File writeArchive(List<ArchiveFile> files) {
    final archive = Archive();
    for (final file in files) {
      archive.add(file);
    }
    final tar = TarEncoder().encode(archive);
    final compressed = BZip2Encoder().encode(tar);
    final path = File('${root.path}/model.tar.bz2')
      ..writeAsBytesSync(compressed);
    return path;
  }

  group('non-regular TAR headers', () {
    for (final type in ['1', '2', '3', '4', '6']) {
      test('should reject TAR type $type before writing any entry', () async {
        final tar = TarEncoder()
            .encode(Archive()..add(ArchiveFile.string('unsafe', '')));
        // Mutate the actual header so device/FIFO flags erased by ArchiveFile
        // still reach the production decoder. Recompute its octal checksum.
        tar[156] = type.codeUnitAt(0);
        for (var i = 148; i < 156; i++) {
          tar[i] = 32;
        }
        final checksum = tar
            .take(512)
            .fold<int>(0, (a, b) => a + b)
            .toRadixString(8)
            .padLeft(6, '0')
            .codeUnits;
        tar.setRange(148, 154, checksum);
        tar[154] = 0;
        tar[155] = 32;
        final file = File('${root.path}/attack.tar.bz2')
          ..writeAsBytesSync(BZip2Encoder().encode(tar));
        final dest = Directory('${root.path}/stage');
        await expectLater(
            extractor.extract(
                archive: file,
                format: TtsArchiveFormat.tarBz2,
                destinationDir: dest),
            throwsA(isA<TtsException>().having(
                (e) => e.code, 'code', TtsErrorCode.modelArchiveInvalid)));
        expect(File('${dest.path}/unsafe').existsSync(), isFalse);
      });
    }
    test('should reject a TAR link target outside staging', () async {
      final archive = writeArchive([
        ArchiveFile.string('safe_link', '')..symbolicLink = '../../outside',
        ArchiveFile.string('safe_link/file', 'evil'),
      ]);
      await expectLater(
          extractor.extract(
              archive: archive,
              format: TtsArchiveFormat.tarBz2,
              destinationDir: Directory('${root.path}/stage')),
          throwsA(isA<TtsException>()));
    });
  });

  test('a benign archive extracts with intact content', () async {
    final modelBytes = Uint8List.fromList(
      List<int>.generate(8192, (i) => (i * 7 + 1) % 256),
    );
    final archive = writeArchive(<ArchiveFile>[
      ArchiveFile.string('payload/tokens.txt', 'tokens'),
      ArchiveFile.bytes('payload/model.int8.onnx', modelBytes),
    ]);
    final dest = Directory('${root.path}/staging');

    await extractor.extract(
      archive: archive,
      format: TtsArchiveFormat.tarBz2,
      destinationDir: dest,
    );

    final tokens = File('${dest.path}/payload/tokens.txt');
    final model = File('${dest.path}/payload/model.int8.onnx');
    expect(tokens.existsSync(), isTrue);
    expect(model.existsSync(), isTrue);
    // Content must be intact — a 0-byte extraction is a silent install failure.
    expect(tokens.readAsStringSync(), 'tokens');
    expect(model.lengthSync(), modelBytes.length);
    expect(model.readAsBytesSync(), modelBytes);
  });

  test('a "../" entry is rejected and nothing escapes', () async {
    final archive = writeArchive(<ArchiveFile>[
      ArchiveFile.string('payload/tokens.txt', 'tokens'),
      ArchiveFile.string('../evil.txt', 'evil'),
    ]);
    final dest = Directory('${root.path}/staging');

    await expectLater(
      extractor.extract(
        archive: archive,
        format: TtsArchiveFormat.tarBz2,
        destinationDir: dest,
      ),
      throwsA(
        isA<TtsException>().having(
          (e) => e.code,
          'code',
          TtsErrorCode.modelArchiveInvalid,
        ),
      ),
    );
    expect(File('${root.path}/evil.txt').existsSync(), isFalse);
  });

  test('an absolute path entry is rejected', () async {
    final archive = writeArchive(<ArchiveFile>[
      ArchiveFile.string('/tmp/lt_absolute_evil.txt', 'evil'),
    ]);
    final dest = Directory('${root.path}/staging');

    await expectLater(
      extractor.extract(
        archive: archive,
        format: TtsArchiveFormat.tarBz2,
        destinationDir: dest,
      ),
      throwsA(isA<TtsException>()),
    );
    expect(File('/tmp/lt_absolute_evil.txt').existsSync(), isFalse);
  });

  // Windows-style entries are rejected on every host because the check is a
  // string normalization, not a filesystem check. This guards the Windows
  // build path even though the test runs on Linux.
  test('Windows drive-letter and backslash entries are rejected', () async {
    for (final name in <String>[
      r'C:\evil.txt',
      r'C:/evil.txt',
      r'..\evil.txt',
      r'..\..\evil.txt',
      r'\evil.txt',
      r'\\server\share\evil.txt',
      r'//server/share/evil.txt',
      r'a/../../evil.txt',
      r'a\..\..\evil.txt',
      r'payload/file:stream',
    ]) {
      final archive = writeArchive(<ArchiveFile>[
        ArchiveFile.string(name, 'evil'),
      ]);
      final dest = Directory('${root.path}/staging_${name.hashCode}');
      await expectLater(
        extractor.extract(
          archive: archive,
          format: TtsArchiveFormat.tarBz2,
          destinationDir: dest,
        ),
        throwsA(isA<TtsException>()),
        reason: 'entry should be rejected: $name',
      );
    }
  });

  test('a benign Windows-style relative path is normalized and accepted',
      () async {
    final archive = writeArchive(<ArchiveFile>[
      ArchiveFile.string(r'payload\model.int8.onnx', 'model'),
    ]);
    final dest = Directory('${root.path}/staging_ok');

    await extractor.extract(
      archive: archive,
      format: TtsArchiveFormat.tarBz2,
      destinationDir: dest,
    );

    final extracted = File('${dest.path}/payload/model.int8.onnx');
    expect(extracted.existsSync(), isTrue);
    expect(extracted.readAsStringSync(), 'model');
  });
}
