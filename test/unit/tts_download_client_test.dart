import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lt_dialogue/domain/tts/tts_errors.dart';
import 'package:lt_dialogue/services/tts/tts_download_client.dart';
import 'package:lt_dialogue/services/tts/tts_storage_error.dart';

void main() {
  group('HttpTtsDownloadClient', () {
    late Directory root;
    late File part;
    final uri = Uri.parse('https://example.invalid/model');
    setUp(() {
      root = Directory.systemTemp.createTempSync('lt_download_test_');
      part = File('${root.path}/model.part');
    });
    tearDown(() => root.deleteSync(recursive: true));

    for (final start in [0, 50, 100]) {
      test('should append only a matching 206 range starting at $start',
          () async {
        await part.writeAsBytes(List.filled(100, 7));
        final client = HttpTtsDownloadClient(
            client: MockClient.streaming((request, _) async {
          expect(request.headers['range'], 'bytes=100-');
          return http.StreamedResponse(
              Stream.value(List.filled(200 - start, 9)), 206,
              headers: {'content-range': 'bytes $start-199/200'},
              contentLength: 200 - start);
        }));
        addTearDown(client.close);
        final operation = client.download(
            uri: uri,
            destination: part,
            expectedTotalBytes: 200,
            onProgress: (received, total) {},
            isCancelled: () => false);
        if (start == 100) {
          final result = await operation;
          expect(result.resumed, isTrue);
          expect(await part.readAsBytes(),
              [...List.filled(100, 7), ...List.filled(100, 9)]);
        } else {
          await expectLater(operation, throwsA(isA<TtsException>()));
          expect(await part.readAsBytes(), List.filled(100, 7));
        }
      });
    }

    for (final initial in [100, 250]) {
      test('should restart 200 response / oversized part ($initial)', () async {
        await part.writeAsBytes(List.filled(initial, 7));
        final client = HttpTtsDownloadClient(
            client: MockClient.streaming((request, _) async {
          expect(
              request.headers['range'], initial == 100 ? 'bytes=100-' : isNull);
          return http.StreamedResponse(Stream.value(List.filled(200, 9)), 200,
              contentLength: 200);
        }));
        addTearDown(client.close);
        final result = await client.download(
            uri: uri,
            destination: part,
            expectedTotalBytes: 200,
            onProgress: (received, total) {},
            isCancelled: () => false);
        expect(result.resumed, isFalse);
        expect(await part.readAsBytes(), List.filled(200, 9));
      });
    }

    test(
        'should discard the queued final chunk and progress after cancellation',
        () async {
      final stream = StreamController<List<int>>();
      final progressed = Completer<void>();
      var cancelled = false;
      final progress = <int>[];
      final client = HttpTtsDownloadClient(
          client: MockClient.streaming((received, total) async {
        return http.StreamedResponse(stream.stream, 200);
      }));
      addTearDown(client.close);
      final future = client.download(
          uri: uri,
          destination: part,
          expectedTotalBytes: 200,
          isCancelled: () => cancelled,
          onProgress: (received, _) {
            progress.add(received);
            if (received == 100) progressed.complete();
          });
      stream.add(List.filled(100, 7));
      await progressed.future;
      cancelled = true;
      stream.add(List.filled(100, 9));
      await expectLater(
          future,
          throwsA(isA<TtsException>()
              .having((error) => error.code, 'code', TtsErrorCode.cancelled)));
      await stream.close();
      expect(await part.length(), 100);
      expect(progress, [0, 100]);
    });

    test('should abort a stalled real HTTP request when cancelled', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final entered = Completer<void>();
      server.listen((request) {
        request.response.headers.contentLength = 200;
        request.response.add(List.filled(100, 7));
        request.response.flush().then((_) => entered.complete());
      });
      final client = HttpTtsDownloadClient();
      var cancelled = false;
      final operation = client.download(
          uri: Uri.parse('http://127.0.0.1:${server.port}/model'),
          destination: part,
          expectedTotalBytes: 200,
          onProgress: (received, total) {},
          isCancelled: () => cancelled);
      await entered.future;
      cancelled = true;
      client.cancel(part);
      await expectLater(
          operation.timeout(const Duration(seconds: 3)),
          throwsA(isA<TtsException>()
              .having((e) => e.code, 'code', TtsErrorCode.cancelled)));
      await client.close();
      await server.close(force: true);
    });
  });

  group('storage exhaustion classification', () {
    for (final code in [28, 122]) {
      test('should classify POSIX storage exhaustion $code', () {
        expect(
            ttsFileSystemFailure(FileSystemException('', '', OSError('', code)),
                    TtsErrorCode.modelInstallFailed,
                    isWindows: false, isMacOS: false)
                .code,
            TtsErrorCode.insufficientStorage);
      });
    }
    for (final code in [39, 112]) {
      test('should classify Windows storage exhaustion $code', () {
        expect(
            ttsFileSystemFailure(FileSystemException('', '', OSError('', code)),
                    TtsErrorCode.modelInstallFailed,
                    isWindows: true)
                .code,
            TtsErrorCode.insufficientStorage);
      });
    }
    test('should retain generic errors and classify Darwin quota', () {
      expect(
          ttsFileSystemFailure(
                  const FileSystemException('', '', OSError('', 69)),
                  TtsErrorCode.modelInstallFailed,
                  isWindows: false,
                  isMacOS: true)
              .code,
          TtsErrorCode.insufficientStorage);
      expect(
          ttsFileSystemFailure(
                  const FileSystemException('', '', OSError('', 5)),
                  TtsErrorCode.modelInstallFailed)
              .code,
          TtsErrorCode.modelInstallFailed);
    });
  });
}
