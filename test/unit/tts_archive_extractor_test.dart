import 'dart:io';

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

  test('a benign archive extracts into the destination', () async {
    final archive = writeArchive(<ArchiveFile>[
      ArchiveFile.string('payload/tokens.txt', 'tokens'),
      ArchiveFile.string('payload/voices.bin', 'voices'),
    ]);
    final dest = Directory('${root.path}/staging');

    await extractor.extract(
      archive: archive,
      format: TtsArchiveFormat.tarBz2,
      destinationDir: dest,
    );

    expect(File('${dest.path}/payload/tokens.txt').existsSync(), isTrue);
    expect(File('${dest.path}/payload/voices.bin').existsSync(), isTrue);
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
}
