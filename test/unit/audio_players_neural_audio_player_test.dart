import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:lt_dialogue/services/tts/neural/audio_players_neural_audio_player.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  group('AudioPlayersNeuralAudioPlayer owned WAV lifecycle', () {
    late Directory temporary;
    late AudioPlayersNeuralAudioPlayer audio;
    late List<_MockAudioPlayer> players;
    late List<StreamController<void>> events;
    late List<String> sourcePaths;
    bool failPreparation = false;
    Completer<void>? prepareGate;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('lt-audio-test-');
      players = [];
      events = [];
      sourcePaths = [];
      failPreparation = false;
      prepareGate = null;
      audio = AudioPlayersNeuralAudioPlayer(
        temporaryDirectoryProvider: () async => temporary,
        playerFactory: () {
          final player = _MockAudioPlayer();
          final stream = StreamController<void>.broadcast();
          players.add(player);
          events.add(stream);
          when(() => player.onPlayerComplete).thenAnswer((_) => stream.stream);
          when(() => player.setReleaseMode(ReleaseMode.stop))
              .thenAnswer((_) async {});
          when(() => player.setVolume(any())).thenAnswer((_) async {});
          when(() => player.setSourceDeviceFile(any(),
              mimeType: any(named: 'mimeType'))).thenAnswer((invocation) async {
            sourcePaths.add(invocation.positionalArguments.first as String);
            await prepareGate?.future;
            if (failPreparation) throw StateError('source failed');
          });
          when(() => player.resume()).thenAnswer((_) async {});
          when(() => player.pause()).thenAnswer((_) async {});
          when(() => player.dispose()).thenAnswer((_) async {});
          return player;
        },
      );
    });
    tearDown(() async {
      await audio.dispose();
      for (final stream in events) {
        await stream.close();
      }
      await temporary.delete(recursive: true);
    });

    Future<void> play() =>
        audio.play(Float32List.fromList([-2, -1, 0, 1, 2]), 24000);
    Future<void> flush() async {
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test('should write valid mono 24kHz 16-bit PCM and clamp samples',
        () async {
      await play();
      final bytes = await File(sourcePaths.single).readAsBytes();
      final header = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(header.getUint32(4, Endian.little), bytes.length - 8);
      expect(header.getUint16(20, Endian.little), 1);
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(24, Endian.little), 24000);
      expect(header.getUint32(28, Endian.little), 48000);
      expect(header.getUint16(32, Endian.little), 2);
      expect(header.getUint16(34, Endian.little), 16);
      expect(header.getUint32(40, Endian.little), 10);
      expect([
        for (var offset = 44; offset < bytes.length; offset += 2)
          header.getInt16(offset, Endian.little)
      ], [
        -32767,
        -32767,
        0,
        32767,
        32767
      ]);
    });

    test(
        'should delete source on completion and reject resume after termination',
        () async {
      var completed = 0;
      final notified = Completer<void>();
      audio.onComplete = () {
        completed++;
        notified.complete();
      };
      await play();
      events.single.add(null);
      await notified.future;
      expect(await temporary.list().toList(), isEmpty);
      expect(completed, 1);
      expect(await audio.resume(), isFalse);
    });

    test('should clean stop, replacement and dispose with one live source',
        () async {
      await play();
      final old = sourcePaths.single;
      await play();
      expect(await File(old).exists(), isFalse);
      expect(await temporary.list().toList(), hasLength(1));
      await audio.stop();
      expect(await temporary.list().toList(), isEmpty);
      await play();
      await audio.dispose();
      expect(await temporary.list().toList(), isEmpty);
    });

    test('should clean preparation failures and propagate a typed failure',
        () async {
      failPreparation = true;
      await expectLater(play(), throwsA(isA<Exception>()));
      expect(await temporary.list().toList(), isEmpty);
    });

    test('should handle native asynchronous errors and clean the audio',
        () async {
      final errors = <Object>[];
      final notified = Completer<void>();
      audio.onError = (error) {
        errors.add(error);
        notified.complete();
      };
      await play();
      events.single.addError(StateError('native output lost'));
      events.single.addError(StateError('duplicate native output error'));
      events.single.add(null);
      await notified.future;
      await flush();
      expect(errors, hasLength(1));
      expect(await temporary.list().toList(), isEmpty);
    });

    test('should cancel delayed source preparation without resuming audio',
        () async {
      prepareGate = Completer<void>();
      final playing = play();
      while (sourcePaths.isEmpty) {
        await flush();
      }
      final stopping = audio.stop();
      prepareGate!.complete();
      await Future.wait([playing, stopping]);
      verifyNever(() => players.single.resume());
      expect(await temporary.list().toList(), isEmpty);
    });

    test('should keep pause/resume source until an actual terminal event',
        () async {
      await play();
      expect(await audio.pause(), isTrue);
      expect(await File(sourcePaths.single).exists(), isTrue);
      expect(await audio.resume(), isTrue);
      await audio.stop();
      expect(await audio.resume(), isFalse);
    });
  });
}
