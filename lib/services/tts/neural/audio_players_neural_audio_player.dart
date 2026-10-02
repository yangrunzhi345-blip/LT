import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../../../domain/tts/tts_errors.dart';
import 'neural_audio_player.dart';

/// `audioplayers` implementation of [NeuralAudioPlayer].
///
/// Generated float samples are wrapped in a small in-memory 16-bit PCM WAV and
/// played through the platform audio backend. This keeps a single, supported
/// audio path across Android, iOS, macOS, Windows, Linux and the web instead of
/// hand-writing per-platform players or shelling out.
class AudioPlayersNeuralAudioPlayer implements NeuralAudioPlayer {
  AudioPlayersNeuralAudioPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer() {
    _completeSub = _player.onPlayerComplete.listen((_) {
      _playing = false;
      _onComplete?.call();
    });
  }

  final AudioPlayer _player;
  StreamSubscription<void>? _completeSub;
  bool _initialized = false;
  bool _playing = false;
  double _volume = 1.0;

  void Function()? _onComplete;
  void Function(Object error)? _onError;

  @override
  bool get isInitialized => _initialized;

  @override
  set onComplete(void Function()? handler) => _onComplete = handler;

  @override
  set onError(void Function(Object error)? handler) => _onError = handler;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      _initialized = true;
    } catch (error) {
      throw TtsException(TtsErrorCode.audioPlaybackFailed, cause: error);
    }
  }

  @override
  Future<void> play(
    Float32List samples,
    int sampleRate, {
    double volume = 1.0,
  }) async {
    if (samples.isEmpty || sampleRate <= 0) return;
    await initialize();
    _volume = volume.clamp(0.0, 1.0);
    try {
      await _player.stop();
      final wav = _encodeWav(samples, sampleRate);
      await _player.setVolume(_volume);
      await _player.setSourceBytes(wav, mimeType: 'audio/wav');
      await _player.resume();
      _playing = true;
    } catch (error) {
      _playing = false;
      final exception = TtsException(
        TtsErrorCode.audioPlaybackFailed,
        cause: error,
      );
      _onError?.call(exception);
      throw exception;
    }
  }

  @override
  Future<void> stop() async {
    _playing = false;
    try {
      await _player.stop();
    } catch (error) {
      throw TtsException(TtsErrorCode.audioPlaybackFailed, cause: error);
    }
  }

  @override
  Future<bool> pause() async {
    if (!_playing) return false;
    try {
      await _player.pause();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> resume() async {
    try {
      await _player.resume();
      _playing = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    await _completeSub?.cancel();
    _completeSub = null;
    try {
      await _player.dispose();
    } catch (_) {
      // Nothing useful to do on dispose.
    }
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
