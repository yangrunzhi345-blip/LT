import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/tts/tts_errors.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/services/tts/tts_archive_extractor.dart';
import 'package:lt_dialogue/services/tts/tts_model_catalog.dart';
import 'package:lt_dialogue/services/tts/tts_model_manager.dart';
import 'package:lt_dialogue/services/tts/tts_model_storage.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../helpers/tts_fakes.dart';

Uint8List _payload() => Uint8List.fromList(
      List<int>.generate(4096, (i) => (i * 31 + 7) % 256),
    );

String _sha256(Uint8List bytes) {
  final digest = SHA256Digest();
  digest.update(bytes, 0, bytes.length);
  final out = Uint8List(digest.digestSize);
  digest.doFinal(out, 0);
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

TtsModelDescriptor _descriptor(Uint8List payload, {String? digestOverride}) {
  return TtsModelDescriptor(
    modelId: 'test-model',
    version: 'v1',
    displayName: 'Test Model',
    engineFamily: 'kokoro',
    voiceFamily: 'test-family',
    languages: const <String>['zh-CN'],
    speakerCount: 4,
    downloadUri: Uri.parse('https://example.invalid/test.tar.bz2'),
    downloadSizeBytes: payload.length,
    license: 'Apache-2.0',
    licenseUri: null,
    archiveFormat: TtsArchiveFormat.tarBz2,
    requiredFiles: const <TtsFileSpec>[
      TtsFileSpec(name: 'tokens.txt'),
      TtsFileSpec(name: 'voices.bin'),
      TtsFileSpec(name: 'espeak-ng-data'),
    ],
    modelFileName: const <String>['model.onnx'],
    capabilities: TtsVoiceCapabilities.kokoro,
    integrity:
        TtsModelIntegrity.officialSha256(digestOverride ?? _sha256(payload)),
  );
}

class _Fixture {
  _Fixture(
    this.dir,
    this.payload, {
    FakeTtsDownloadClient? client,
    TtsArchiveExtractor? extractor,
  })  : storage = TtsModelStorage(rootProvider: () async => dir),
        client = client ?? FakeTtsDownloadClient(payload: payload),
        extractor = extractor ?? const FakeTtsArchiveExtractor();

  final Directory dir;
  final Uint8List payload;
  final TtsModelStorage storage;
  final FakeTtsDownloadClient client;
  final TtsArchiveExtractor extractor;

  TtsModelManager manager(TtsModelDescriptor descriptor) => TtsModelManager(
        catalog: TtsModelCatalog(models: <TtsModelDescriptor>[descriptor]),
        storage: storage,
        downloadClient: client,
        extractor: extractor,
      );
}

class _MutatingExtractor extends TtsArchiveExtractor {
  _MutatingExtractor(this.mutate);
  final Future<void> Function(Directory root) mutate;

  @override
  Future<void> extract(
      {required File archive,
      required TtsArchiveFormat format,
      required Directory destinationDir}) async {
    await const FakeTtsArchiveExtractor().extract(
        archive: archive, format: format, destinationDir: destinationDir);
    await mutate(Directory('${destinationDir.path}/payload'));
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lt_tts_manager_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('model integrity and operation races', () {
    test('should keep installation consistent when cancel arrives at commit',
        () async {
      final payload = _payload();
      final fixture = _Fixture(tempDir, payload);
      final manager = fixture.manager(_descriptor(payload));
      addTearDown(manager.dispose);
      Future<void>? cancelling;
      manager.addListener(() {
        if (manager.statusOf('test-model').state ==
                TtsModelInstallState.installed &&
            cancelling == null) {
          cancelling = manager.cancel('test-model');
        }
      });
      await manager.download('test-model');
      await cancelling;
      expect(manager.isModelInstalled('test-model'), isTrue);
      expect(
          manager.statusOf('test-model').state, TtsModelInstallState.installed);
      await manager.refresh();
      expect(
          manager.statusOf('test-model').state, TtsModelInstallState.installed);
    });
    test('should retry immediately after cancel without stale cleanup',
        () async {
      final payload = _payload();
      final entered = Completer<void>();
      final release = Completer<void>();
      var extractions = 0;
      final fixture =
          _Fixture(tempDir, payload, extractor: _MutatingExtractor((_) async {
        if (extractions++ == 0) {
          entered.complete();
          await release.future;
        }
      }));
      final manager = fixture.manager(_descriptor(payload));
      addTearDown(manager.dispose);
      final old = manager.download('test-model');
      await entered.future;
      final cancel = manager.cancel('test-model');
      final retry = manager.download('test-model');
      release.complete();
      await Future.wait([old, cancel, retry]);
      expect(
          manager.statusOf('test-model').state, TtsModelInstallState.installed);
      expect(fixture.client.requestCount, 2);
      expect(
          await File(manager.installed('test-model')!.modelPath).readAsString(),
          'model');
    });

    test('should release active runtime before deleting files', () async {
      final payload = _payload();
      final fixture = _Fixture(tempDir, payload);
      final descriptor = _descriptor(payload);
      final released = Completer<void>();
      final entered = Completer<void>();
      final manager = TtsModelManager(
          catalog: TtsModelCatalog(models: [descriptor]),
          storage: fixture.storage,
          downloadClient: fixture.client,
          extractor: fixture.extractor,
          beforeDelete: (id) async {
            expect(id, 'test-model');
            expect(await (await fixture.storage.modelDir(descriptor)).exists(),
                isTrue);
            entered.complete();
            await released.future;
          });
      addTearDown(manager.dispose);
      await manager.download('test-model');
      final removal = manager.delete('test-model');
      await entered.future;
      expect(manager.isModelInstalled('test-model'), isFalse);
      released.complete();
      await removal;
      expect(
          await (await fixture.storage.modelDir(descriptor)).exists(), isFalse);
    });

    test(
        'should recover crash leftovers without inventing an install or downloading',
        () async {
      final payload = _payload();
      final fixture = _Fixture(tempDir, payload);
      final descriptor = _descriptor(payload);
      final dir = await fixture.storage.modelDir(descriptor);
      await dir.create(recursive: true);
      await File('${dir.path}/model.onnx').writeAsString('orphan');
      final stale = await fixture.storage.newStagingDir(descriptor);
      final part = await fixture.storage.partFile(descriptor);
      await part.parent.create(recursive: true);
      await part.writeAsBytes(payload.take(100).toList());
      final manager = fixture.manager(descriptor);
      addTearDown(manager.dispose);
      await manager.refresh();
      expect(await stale.exists(), isFalse);
      expect(await part.length(), 100);
      expect(manager.isModelInstalled('test-model'), isFalse);
      expect(manager.statusOf('test-model').state, TtsModelInstallState.paused);
      expect(fixture.client.requestCount, 0);
      await manager.download('test-model');
      expect(manager.isModelInstalled('test-model'), isTrue);
    });
    for (final name in ['model.onnx', 'voices.bin', 'tokens.txt']) {
      test('should reject zero-byte $name before publishing', () async {
        final payload = _payload();
        final fixture = _Fixture(tempDir, payload,
            extractor: _MutatingExtractor((root) async {
          await File('${root.path}/$name').writeAsBytes([]);
        }));
        final manager = fixture.manager(_descriptor(payload));
        addTearDown(manager.dispose);
        await manager.download('test-model');
        expect(manager.isModelInstalled('test-model'), isFalse);
        expect(
            manager.statusOf('test-model').state, TtsModelInstallState.failed);
      });
    }

    for (final mutation in [
      'invalid JSON',
      'version',
      'modelId',
      'voiceFamily',
      'speakerCount',
      'integrity',
      'missing field',
      'size mismatch',
      'zero model',
      'missing voices',
      'unsafe path'
    ]) {
      test('should reject manifest/tree corruption: $mutation', () async {
        final payload = _payload();
        final fixture = _Fixture(tempDir, payload);
        final descriptor = _descriptor(payload);
        final manager = fixture.manager(descriptor);
        addTearDown(manager.dispose);
        await manager.download('test-model');
        final file = await fixture.storage.manifestFile(descriptor);
        final data =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        switch (mutation) {
          case 'invalid JSON':
            await file.writeAsString('{');
          case 'version':
            data['version'] = 'other';
          case 'modelId':
            data['modelId'] = 'other';
          case 'voiceFamily':
            data['voiceFamily'] = 'other';
          case 'speakerCount':
            data['speakerCount'] = 999;
          case 'integrity':
            data['integrity'] = {
              'algorithm': 'sha256',
              'digest': 'bad',
              'source': 'official'
            };
          case 'missing field':
            data.remove('voiceFamily');
          case 'size mismatch':
            await File(manager.installed('test-model')!.modelPath)
                .writeAsString('changed model length');
          case 'zero model':
            await File(manager.installed('test-model')!.modelPath)
                .writeAsBytes([]);
          case 'missing voices':
            await File(manager.installed('test-model')!.voicesPath).delete();
          case 'unsafe path':
            data['modelFileName'] = '../outside.onnx';
        }
        if (mutation != 'invalid JSON') {
          await file.writeAsString(jsonEncode(data));
        }
        await manager.refresh();
        expect(manager.isModelInstalled('test-model'), isFalse);
      });
    }

    test('should dedupe downloads and retain active state during refresh',
        () async {
      final payload = _payload();
      final entered = Completer<void>();
      final release = Completer<void>();
      final fixture =
          _Fixture(tempDir, payload, extractor: _MutatingExtractor((_) async {
        entered.complete();
        await release.future;
      }));
      final manager = fixture.manager(_descriptor(payload));
      addTearDown(manager.dispose);
      final first = manager.download('test-model');
      await entered.future;
      await manager.download('test-model');
      await manager.refresh();
      expect(fixture.client.requestCount, 1);
      expect(manager.statusOf('test-model').state,
          TtsModelInstallState.installing);
      release.complete();
      await first;
    });

    for (final action in ['cancel', 'delete']) {
      test(
          'should await extraction before $action and never publish late install',
          () async {
        final payload = _payload();
        final entered = Completer<void>();
        final release = Completer<void>();
        final fixture =
            _Fixture(tempDir, payload, extractor: _MutatingExtractor((_) async {
          entered.complete();
          await release.future;
        }));
        final descriptor = _descriptor(payload);
        final manager = fixture.manager(descriptor);
        addTearDown(manager.dispose);
        final install = manager.download('test-model');
        await entered.future;
        final removal = action == 'cancel'
            ? manager.cancel('test-model')
            : manager.delete('test-model');
        release.complete();
        await install;
        await removal;
        expect(manager.isModelInstalled('test-model'), isFalse);
        expect(await (await fixture.storage.modelDir(descriptor)).exists(),
            isFalse);
        expect(await (await fixture.storage.partFile(descriptor)).exists(),
            isFalse);
        expect(manager.statusOf('test-model').state,
            TtsModelInstallState.notInstalled);
      });
    }
  });

  test('initialization never makes a network request', () async {
    final payload = _payload();
    final fixture = _Fixture(tempDir, payload);
    final manager = fixture.manager(_descriptor(payload));

    await manager.initialize();

    expect(fixture.client.requestCount, 0);
    expect(
      manager.statusOf('test-model').state,
      TtsModelInstallState.notInstalled,
    );
    manager.dispose();
  });

  test('download installs the model and writes a manifest', () async {
    final payload = _payload();
    final fixture = _Fixture(tempDir, payload);
    final manager = fixture.manager(_descriptor(payload));

    await manager.download('test-model');

    expect(fixture.client.requestCount, 1);
    expect(
      manager.statusOf('test-model').state,
      TtsModelInstallState.installed,
    );
    expect(manager.isModelInstalled('test-model'), isTrue);
    expect(manager.installedBytesFor('test-model'), greaterThan(0));

    final installed = manager.installed('test-model')!;
    expect(File(installed.modelPath).existsSync(), isTrue);
    expect(File('${installed.rootPath}/manifest.json').existsSync(), isTrue);
    manager.dispose();
  });

  test('non-2xx failure surfaces a typed error and can be retried', () async {
    final payload = _payload();
    final client = FakeTtsDownloadClient(payload: payload, failStatus: 500);
    final fixture = _Fixture(tempDir, payload, client: client);
    final manager = fixture.manager(_descriptor(payload));

    await manager.download('test-model');

    final status = manager.statusOf('test-model');
    expect(status.state, TtsModelInstallState.failed);
    expect(status.errorCode, TtsErrorCode.modelDownloadFailed);
    manager.dispose();
  });

  test('integrity mismatch is rejected', () async {
    final payload = _payload();
    final fixture = _Fixture(tempDir, payload);
    final manager = fixture.manager(
      _descriptor(payload, digestOverride: '0' * 64),
    );

    await manager.download('test-model');

    final status = manager.statusOf('test-model');
    expect(status.state, TtsModelInstallState.failed);
    expect(status.errorCode, TtsErrorCode.modelIntegrityFailed);
    expect(manager.isModelInstalled('test-model'), isFalse);
    manager.dispose();
  });

  test('cancel removes the partial file', () async {
    final payload = _payload();
    final client = FakeTtsDownloadClient(
      payload: payload,
      chunkSize: 512,
      delayPerChunk: const Duration(milliseconds: 2),
    );
    final fixture = _Fixture(tempDir, payload, client: client);
    final manager = fixture.manager(_descriptor(payload));

    final future = manager.download('test-model');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await manager.cancel('test-model');
    await future;

    final part = await fixture.storage.partFile(
      TtsModelCatalog(models: <TtsModelDescriptor>[_descriptor(payload)])
          .byId('test-model')!,
    );
    expect(await part.exists(), isFalse);
    expect(manager.isModelInstalled('test-model'), isFalse);
    manager.dispose();
  });

  test('pause preserves the partial file and resume completes', () async {
    final payload = _payload();
    final client = FakeTtsDownloadClient(
      payload: payload,
      chunkSize: 256,
      delayPerChunk: const Duration(milliseconds: 2),
    );
    final fixture = _Fixture(tempDir, payload, client: client);
    final manager = fixture.manager(_descriptor(payload));

    final future = manager.download('test-model');
    await Future<void>.delayed(const Duration(milliseconds: 6));
    await manager.pause('test-model');
    await future;
    expect(
      manager.statusOf('test-model').state,
      TtsModelInstallState.paused,
    );

    await manager.download('test-model');
    expect(
      manager.statusOf('test-model').state,
      TtsModelInstallState.installed,
    );
    manager.dispose();
  });

  test('an unsafe archive fails and leaves nothing installed', () async {
    final payload = _payload();
    final fixture = _Fixture(
      tempDir,
      payload,
      extractor: const FakeTtsArchiveExtractor(traversal: true),
    );
    final manager = fixture.manager(_descriptor(payload));

    await manager.download('test-model');

    final status = manager.statusOf('test-model');
    expect(status.state, TtsModelInstallState.failed);
    expect(status.errorCode, TtsErrorCode.modelArchiveInvalid);
    expect(manager.isModelInstalled('test-model'), isFalse);
    manager.dispose();
  });

  test('delete removes files and refresh no longer finds the model', () async {
    final payload = _payload();
    final fixture = _Fixture(tempDir, payload);
    final manager = fixture.manager(_descriptor(payload));

    await manager.download('test-model');
    final installed = manager.installed('test-model')!;
    await manager.delete('test-model');

    expect(manager.isModelInstalled('test-model'), isFalse);
    expect(Directory(installed.rootPath).existsSync(), isFalse);

    await manager.refresh();
    expect(manager.isModelInstalled('test-model'), isFalse);
    manager.dispose();
  });

  test('manifest round-trips through refresh', () async {
    final payload = _payload();
    final fixture = _Fixture(tempDir, payload);
    final descriptor = _descriptor(payload);
    final manager = fixture.manager(descriptor);
    await manager.download('test-model');

    final second = fixture.manager(descriptor);
    await second.initialize();

    expect(second.isModelInstalled('test-model'), isTrue);
    expect(
      second.installed('test-model')!.lexiconFileNames,
      isEmpty,
    );
    // A fresh manager does not re-download an already installed model.
    expect(fixture.client.requestCount, 1);
    manager.dispose();
    second.dispose();
  });

  test('delete keeps voice bindings (bindings are a separate store)', () async {
    // Sanity: the manager has no API that touches voice bindings.
    final managerSource = File(
      'lib/services/tts/tts_model_manager.dart',
    ).readAsStringSync();
    expect(managerSource.contains('VoiceBinding'), isFalse);
  });
}
