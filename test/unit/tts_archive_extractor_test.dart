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
