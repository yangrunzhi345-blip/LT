import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/tts/tts_errors.dart';
import 'tts_storage_error.dart';

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

  /// Interrupts the current request for this file; implementations may be no-op.
  void cancel(File destination) {}

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
    if (isCancelled()) throw const TtsException(TtsErrorCode.cancelled);
    var offset = await destination.exists() ? await destination.length() : 0;
    if (offset > expectedTotalBytes) {
      await destination.delete();
      offset = 0;
    }
    if (offset == expectedTotalBytes && offset > 0) {
      return TtsDownloadOutcome(
          bytesWritten: offset, resumed: true, totalBytes: expectedTotalBytes);
    }
    final abort = Completer<void>();
    _requests[destination.absolute.path] = abort;
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abort.future);
    request.headers[HttpHeaders.acceptEncodingHeader] = 'identity';
    if (offset > 0) request.headers[HttpHeaders.rangeHeader] = 'bytes=$offset-';

    RandomAccessFile? writer;
    try {
      final response = await _client.send(request).timeout(_timeout);
      if (isCancelled()) throw const TtsException(TtsErrorCode.cancelled);
      final status = response.statusCode;
      if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
        await response.stream.take(0).drain<void>();
        throw TtsException(TtsErrorCode.modelDownloadFailed,
            detail: 'HTTP $status');
      }
      final resumed = status == HttpStatus.partialContent && offset > 0;
      if (status == HttpStatus.partialContent) {
        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
            .firstMatch(response.headers['content-range'] ?? '');
        final start = range == null ? null : int.tryParse(range[1]!);
        final end = range == null ? null : int.tryParse(range[2]!);
        final total = range == null ? null : int.tryParse(range[3]!);
        if (start != offset ||
            end == null ||
            end < offset ||
            total != expectedTotalBytes ||
            end != expectedTotalBytes - 1 ||
            (response.contentLength != null &&
                response.contentLength != end - offset + 1)) {
          await response.stream.take(0).drain<void>();
          throw const TtsException(TtsErrorCode.modelDownloadFailed,
              detail: 'invalid Content-Range');
        }
      } else {
        offset = 0;
        if (response.contentLength != null &&
            response.contentLength != expectedTotalBytes) {
          await response.stream.take(0).drain<void>();
          throw const TtsException(TtsErrorCode.modelDownloadFailed,
              detail: 'invalid Content-Length');
        }
      }
      if (isCancelled()) throw const TtsException(TtsErrorCode.cancelled);
      writer = await destination.open(
          mode: resumed ? FileMode.append : FileMode.write);
      var received = offset;
      if (!isCancelled()) onProgress(received, expectedTotalBytes);
      await for (final chunk in response.stream.timeout(_timeout)) {
        if (isCancelled()) throw const TtsException(TtsErrorCode.cancelled);
        if (received + chunk.length > expectedTotalBytes) {
          throw const TtsException(TtsErrorCode.modelIntegrityFailed,
              detail: 'response exceeds expected size');
        }
        await writer.writeFrom(chunk);
        received += chunk.length;
        if (!isCancelled()) onProgress(received, expectedTotalBytes);
      }
      if (isCancelled()) throw const TtsException(TtsErrorCode.cancelled);
      await writer.flush();
      return TtsDownloadOutcome(
          bytesWritten: received,
          resumed: resumed,
          totalBytes: expectedTotalBytes);
    } on TtsException {
      rethrow;
    } on FileSystemException catch (error) {
      throw ttsFileSystemFailure(error, TtsErrorCode.modelDownloadFailed);
    } catch (error) {
      if (isCancelled()) throw const TtsException(TtsErrorCode.cancelled);
      throw TtsException(TtsErrorCode.networkUnavailable, cause: error);
    } finally {
      if (!abort.isCompleted) abort.complete();
      if (identical(_requests[destination.absolute.path], abort)) {
        _requests.remove(destination.absolute.path);
      }
      await writer?.close();
    }
  }

  final Map<String, Completer<void>> _requests = {};

  @override
  void cancel(File destination) {
    final abort = _requests[destination.absolute.path];
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  @override
  Future<void> close() async {
    for (final abort in _requests.values) {
      if (!abort.isCompleted) abort.complete();
    }
    _client.close();
  }
}
