import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/tts/tts_errors.dart';

/// Progress callback: bytes already on disk and total bytes (0 if unknown).
typedef TtsProgressCallback = void Function(int received, int total);

/// Result of a completed download.
class TtsDownloadOutcome {
  const TtsDownloadOutcome({
    required this.bytesWritten,
    required this.resumed,
    required this.totalBytes,
  });

  final int bytesWritten;
  final bool resumed;
  final int totalBytes;
}

/// Downloads a model archive into a `.part` file.
///
/// Abstracted so tests can exercise the model manager without any network.
/// Production uses [HttpTtsDownloadClient]; the app never shells out to
/// `wget`/`curl`/`tar`.
abstract class TtsDownloadClient {
  Future<TtsDownloadOutcome> download({
    required Uri uri,
    required File destination,
    required int expectedTotalBytes,
    required TtsProgressCallback onProgress,
    required bool Function() isCancelled,
  });

  Future<void> close();
}

/// `package:http` based downloader with Range resume and cancellation.
class HttpTtsDownloadClient implements TtsDownloadClient {
  HttpTtsDownloadClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 30);

  @override
  Future<TtsDownloadOutcome> download({
    required Uri uri,
    required File destination,
    required int expectedTotalBytes,
    required TtsProgressCallback onProgress,
    required bool Function() isCancelled,
  }) async {
    var offset = 0;
    if (await destination.exists()) {
      offset = await destination.length();
    }

    final request = http.Request('GET', uri);
    request.headers[HttpHeaders.acceptEncodingHeader] = 'identity';
    if (offset > 0) {
      request.headers[HttpHeaders.rangeHeader] = 'bytes=$offset-';
    }

    http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_timeout);
    } on TimeoutException catch (error) {
      throw TtsException(TtsErrorCode.networkUnavailable, cause: error);
    } on SocketException catch (error) {
      throw TtsException(TtsErrorCode.networkUnavailable, cause: error);
    } on http.ClientException catch (error) {
      throw TtsException(TtsErrorCode.networkUnavailable, cause: error);
    }

    final status = response.statusCode;
    final serverHonoursRange = status == HttpStatus.partialContent;
    if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
      throw TtsException(
        TtsErrorCode.modelDownloadFailed,
        detail: 'HTTP $status',
      );
    }

    // If the server ignored our Range request, restart from scratch.
    var resumed = serverHonoursRange && offset > 0;
    if (status == HttpStatus.ok) {
      offset = 0;
      resumed = false;
      if (await destination.exists()) await destination.delete();
    }

    final contentLength = response.contentLength ?? 0;
    final declaredTotal = response.headers['content-range'];
    var total = expectedTotalBytes;
    if (declaredTotal != null) {
      final slash = declaredTotal.lastIndexOf('/');
      if (slash >= 0) {
        final parsed = int.tryParse(declaredTotal.substring(slash + 1).trim());
        if (parsed != null && parsed > 0) total = parsed;
      }
    } else if (contentLength > 0) {
      total = offset + contentLength;
    }
    if (total <= 0) total = expectedTotalBytes;

    final sink = destination.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    var received = offset;
    onProgress(received, total);
    try {
      await for (final chunk in response.stream) {
        if (isCancelled()) {
          throw const TtsException(TtsErrorCode.cancelled);
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
    } on TtsException {
      await sink.close().catchError((_) {});
      rethrow;
    } catch (error) {
      await sink.close().catchError((_) {});
      throw TtsException(
        TtsErrorCode.modelDownloadFailed,
        detail: 'write failed',
        cause: error,
      );
    }

    return TtsDownloadOutcome(
      bytesWritten: received,
      resumed: resumed,
      totalBytes: total,
    );
  }

  @override
  Future<void> close() async => _client.close();
}
