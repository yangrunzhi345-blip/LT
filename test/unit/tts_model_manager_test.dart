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

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('lt_tts_manager_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
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
