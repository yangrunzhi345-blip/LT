import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:lt_dialogue/services/tts/neural/audio_players_neural_audio_player.dart';

import '../helpers/tts_real_model_validation.dart';

/// Run explicitly with `flutter run -d linux -t` and the defines below.
/// Exercises the production desktop plugin; unit-test plugin fakes are absent.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const rootPath = String.fromEnvironment('LT_TTS_E2E_ROOT');
  if (rootPath.isEmpty || !const bool.fromEnvironment('LT_TTS_REAL_AUDIO')) {
    throw StateError(
        'Explicit LT_TTS_REAL_AUDIO=true and isolated root required');
  }
  runApp(const SizedBox.shrink());
  final player = AudioPlayersNeuralAudioPlayer();
  var exitCode = 1;
  try {
    final report = await validateRealTtsModel(
      root: Directory(rootPath),
      allowDownload: const bool.fromEnvironment('LT_TTS_ALLOW_DOWNLOAD'),
      play: (label, result) async {
        final completed = Completer<void>();
        player.onComplete = () {
          if (!completed.isCompleted) completed.complete();
        };
        player.onError = (error) {
          if (!completed.isCompleted) completed.completeError(error);
        };
        await player.play(result.samples, result.sampleRate);
        await completed.future.timeout(const Duration(seconds: 30));
        // ignore: avoid_print
        print('PLAYED $label');
      },
    );
    // ignore: avoid_print
    print(report);
    exitCode = 0;
  } catch (error, stackTrace) {
    stderr.writeln('Real audio validation failed: $error\n$stackTrace');
  } finally {
    await player.dispose();
    exit(exitCode);
  }
}
