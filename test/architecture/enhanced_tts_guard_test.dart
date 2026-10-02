import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_imports.dart';

bool _isPresentation(String path) =>
    path.startsWith('lib/features/') && path.contains('/presentation/');

void main() {
  const flutterTtsBoundary = 'lib/services/read_aloud/flutter_tts_engine.dart';
  const sherpaBoundary =
      'lib/services/tts/neural/sherpa_neural_tts_engine.dart';
  const audioBoundary =
      'lib/services/tts/neural/audio_players_neural_audio_player.dart';

  test('flutter_tts is only imported by the single system engine boundary', () {
    final importers = collectImports('lib')
        .where((i) => i.uri.startsWith('package:flutter_tts/'))
        .map((i) => i.importer)
        .toSet();
    expect(importers, <String>{flutterTtsBoundary});
  });

  test('sherpa_onnx is only imported by the neural engine boundary', () {
    final importers = collectImports('lib')
        .where((i) => i.uri.startsWith('package:sherpa_onnx/'))
        .map((i) => i.importer)
        .toSet();
    expect(importers, <String>{sherpaBoundary});
  });

  test('audioplayers is only imported by the neural audio boundary', () {
    final importers = collectImports('lib')
        .where((i) => i.uri.startsWith('package:audioplayers/'))
        .map((i) => i.importer)
        .toSet();
    expect(importers, <String>{audioBoundary});
  });

  test('presentation never imports TTS implementation packages', () {
    final violations = collectImports('lib')
        .where((i) =>
            _isPresentation(i.importer) &&
            (i.uri.startsWith('package:flutter_tts/') ||
                i.uri.startsWith('package:sherpa_onnx/') ||
                i.uri.startsWith('package:audioplayers/')))
        .map((i) => i.edge)
        .toList();
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('ReadAloudController has exactly one composition root', () {
    const allowed = <String>{
      'lib/services/read_aloud/read_aloud_controller.dart',
      'lib/providers/riverpod_providers.dart',
      'lib/providers/settings_provider.dart',
    };
    final pattern = RegExp(r'\bReadAloudController\s*\(');
    final offenders = <String>[];
    for (final path in dartFilesUnder('lib')) {
      if (allowed.contains(path)) continue;
      if (pattern.hasMatch(File(path).readAsStringSync())) offenders.add(path);
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('character/NPC drafts never store TTS voice identity', () {
    final source = File(
      'lib/application/resource_library/edit_drafts.dart',
    ).readAsStringSync();
    for (final token in <String>[
      'ttsModelId',
      'speakerId',
      'localModelPath',
      'ttsVoiceId',
      'voiceId',
      'tts_voice',
    ]) {
      expect(source.contains(token), isFalse, reason: token);
    }
  });

  test('no neural model binaries are shipped in assets', () {
    final dir = Directory('assets');
    if (!dir.existsSync()) return;
    final binaries = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) {
          final path = file.path.toLowerCase();
          return path.endsWith('.onnx') ||
              path.endsWith('.bin') ||
              path.endsWith('.fst') ||
              path.endsWith('.tar.bz2');
        })
        .map((file) => file.path)
        .toList();
    expect(binaries, isEmpty, reason: binaries.join('\n'));
  });

  test('the model manager is the only download entry point', () {
    // Only the manager (and its transport implementations) may reference the
    // download client; UI must go through the manager.
    final importers = collectImports('lib')
        .where((i) => i.target == 'lib/services/tts/tts_download_client.dart')
        .map((i) => i.importer)
        .toSet();
    expect(
      importers,
      contains('lib/services/tts/tts_model_manager.dart'),
    );
    expect(importers.every((p) => !_isPresentation(p)), isTrue);
  });
}
