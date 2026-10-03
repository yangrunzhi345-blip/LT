import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../domain/tts/tts_errors.dart';
import 'neural_audio_player.dart';

/// Plays an owned temporary WAV, freeing its player and source on termination.
///
/// audioplayers' setSourceBytes silently writes unowned files on Linux/Darwin.
/// Explicit files and a fresh player per source also isolate delayed platform
/// events belonging to a previous utterance.
class AudioPlayersNeuralAudioPlayer implements NeuralAudioPlayer {
  AudioPlayersNeuralAudioPlayer(
      {AudioPlayer? player,
      AudioPlayer Function()? playerFactory,
      Future<Directory> Function()? temporaryDirectoryProvider})
      : _initialPlayer = player,
        _playerFactory = playerFactory ?? AudioPlayer.new,
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? getTemporaryDirectory;

  AudioPlayer? _initialPlayer;
  final AudioPlayer Function() _playerFactory;
  final Future<Directory> Function() _temporaryDirectoryProvider;
  AudioPlayer? _player;
  Directory? _audioDirectory;
  StreamSubscription<void>? _completeSub;
  bool _initialized = false;
  bool _playing = false;
  bool _paused = false;
  bool _disposed = false;
  int _generation = 0;
  Future<void> _operations = Future<void>.value();
  void Function()? _onComplete;
  void Function(Object error)? _onError;

  @override
  bool get isInitialized => _initialized;
  @override
  set onComplete(void Function()? handler) => _onComplete = handler;
  @override
  set onError(void Function(Object error)? handler) => _onError = handler;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _operations.then((_) => operation());
    _operations = result.then((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<void> initialize() async {
    // Players are initialized inside play, so no platform resources are held
    // while an utterance is still being inferred.
    if (!_disposed) _initialized = true;
  }

  @override
  Future<void> play(Float32List samples, int sampleRate, {double volume = 1}) {
    final generation = ++_generation;
    final complete = _onComplete;
    final errorHandler = _onError;
    return _serialize(() async {
      await _releaseSource();
      if (!_isCurrent(generation) || samples.isEmpty || sampleRate <= 0) return;
      try {
        final player = _initialPlayer ?? _playerFactory();
        _initialPlayer = null;
        _player = player;
        var terminal = false;
        final tempRoot = await _temporaryDirectoryProvider();
        if (!_isCurrent(generation)) {
          await _releaseSource();
          return;
        }
        final directory = await tempRoot.createTemp('lt-tts-');
        _audioDirectory = directory;
        final file = File(p.join(directory.path, 'speech.wav'));
        await file.writeAsBytes(_encodeWav(samples, sampleRate), flush: true);
        if (!_isCurrent(generation)) {
          await _releaseSource();
          return;
        }
        _completeSub = player.onPlayerComplete.listen((_) {
          if (!_isCurrent(generation) || terminal) return;
          terminal = true;
          _playing = false;
          _paused = false;
          unawaited(_serialize(() async {
            if (!_isCurrent(generation)) return;
            await _releaseSource();
            if (_isCurrent(generation)) complete?.call();
          }));
        }, onError: (Object error) {
          if (!_isCurrent(generation) || terminal) return;
          terminal = true;
          _playing = false;
          _paused = false;
          unawaited(_serialize(() async {
            if (!_isCurrent(generation)) return;
            await _releaseSource();
            if (_isCurrent(generation)) {
              errorHandler?.call(
                  TtsException(TtsErrorCode.audioPlaybackFailed, cause: error));
            }
          }));
        });
        await player.setReleaseMode(ReleaseMode.stop);
        if (!_isCurrent(generation)) return;
        await player.setVolume(volume.clamp(0.0, 1.0));
        if (!_isCurrent(generation)) return;
        await player.setSourceDeviceFile(file.path, mimeType: 'audio/wav');
        if (!_isCurrent(generation)) return;
        await player.resume();
        if (_isCurrent(generation)) {
          _initialized = true;
          _playing = true;
        }
      } catch (error) {
        await _releaseSource();
        if (!_isCurrent(generation)) return;
        // Initial preparation failures are returned to the routing engine;
        // only delayed playback-stream errors use onError, avoiding duplicate
        // fallback for the same failure.
        throw TtsException(TtsErrorCode.audioPlaybackFailed, cause: error);
      } finally {
        if (!_isCurrent(generation)) await _releaseSource();
      }
    });
  }

  Future<void> _releaseSource() async {
    final subscription = _completeSub;
    final player = _player;
    final directory = _audioDirectory;
    _completeSub = null;
    _player = null;
    _audioDirectory = null;
    _playing = false;
    _paused = false;
    try {
      await subscription?.cancel();
    } catch (error) {
      debugPrint('[ReadAloud] Audio subscription release failed: $error');
    }
    try {
      await player?.dispose();
    } catch (error) {
      debugPrint('[ReadAloud] Audio resource release failed: $error');
    } finally {
      if (directory != null) {
        try {
          if (await directory.exists()) await directory.delete(recursive: true);
        } catch (error) {
          debugPrint('[ReadAloud] Temporary audio cleanup failed: $error');
        }
      }
    }
  }

  @override
  Future<void> stop() {
    _generation++;
    _playing = false;
    _paused = false;
    return _serialize(_releaseSource);
  }

  @override
  Future<bool> pause() async {
    if (!_playing || _disposed) return false;
    final generation = _generation;
    try {
      await _player?.pause();
      if (!_isCurrent(generation)) return false;
      _playing = false;
      _paused = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> resume() async {
    if (!_paused || _disposed || _player == null) return false;
    final generation = _generation;
    try {
      await _player!.resume();
      if (!_isCurrent(generation)) return false;
      _playing = true;
      _paused = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _onComplete = null;
    _onError = null;
    await stop();
    final initial = _initialPlayer;
    _initialPlayer = null;
    await initial?.dispose();
  }

  /// Encodes mono float samples as a 16-bit PCM WAV file.
  static Uint8List _encodeWav(Float32List samples, int sampleRate) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final dataLength = samples.length * 2;
    final buffer = BytesBuilder();
    final header = ByteData(44);

    // 'RIFF'
    header.setUint8(0, 0x52);
    header.setUint8(1, 0x49);
    header.setUint8(2, 0x46);
    header.setUint8(3, 0x46);
    header.setUint32(4, 36 + dataLength, Endian.little);
    // 'WAVE'
    header.setUint8(8, 0x57);
    header.setUint8(9, 0x41);
    header.setUint8(10, 0x56);
    header.setUint8(11, 0x45);
    // 'fmt '
    header.setUint8(12, 0x66);
    header.setUint8(13, 0x6d);
    header.setUint8(14, 0x74);
    header.setUint8(15, 0x20);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // 'data'
    header.setUint8(36, 0x64);
    header.setUint8(37, 0x61);
    header.setUint8(38, 0x74);
    header.setUint8(39, 0x61);
    header.setUint32(40, dataLength, Endian.little);
    buffer.add(header.buffer.asUint8List());

    final pcm = ByteData(dataLength);
    for (var i = 0; i < samples.length; i++) {
      final clamped = samples[i].clamp(-1.0, 1.0);
      final value = (clamped * 32767).round();
      pcm.setInt16(i * 2, value, Endian.little);
    }
    buffer.add(pcm.buffer.asUint8List());
    return buffer.toBytes();
  }
}
