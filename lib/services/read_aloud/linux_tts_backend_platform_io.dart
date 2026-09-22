import 'dart:async';
import 'dart:io';

import 'linux_tts_backend_contract.dart';

LinuxTtsBackend createLinuxTtsBackend() => _SpdSayLinuxTtsBackend();

final class _SpdSayLinuxTtsBackend implements LinuxTtsBackend {
  Process? _activeProcess;
  final Map<String, String> _voicesByLanguage = <String, String>{};

  @override
  Future<bool> isAvailable() async {
    try {
      // Listing synthesis voices verifies both the executable and the
      // Speech Dispatcher connection without producing audible output.
      final result = await Process.run('spd-say', <String>['-L']);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<List<String>> availableLanguages() async {
    try {
      final result = await Process.run('spd-say', <String>['-L']);
      if (result.exitCode != 0) return const <String>[];
      final tags = <String>{};
      for (final line in result.stdout.toString().split('\n')) {
        final columns = line.trim().split(RegExp(r'\s{2,}'));
        if (columns.length >= 2 && _looksLikeLanguageTag(columns[1])) {
          final language = columns[1].replaceAll('_', '-');
          tags.add(language);
          _voicesByLanguage.putIfAbsent(
              language.toLowerCase(), () => columns[0]);
        }
      }
      return tags.toList()..sort();
    } on ProcessException {
      return const <String>[];
    }
  }

  @override
  Future<void> speak(
    String text, {
    required double rate,
    required double pitch,
    required double volume,
    String? language,
  }) async {
    await stop();
    final voice = language == null ? null : _voiceForLanguage(language);
    final args = <String>[
      // Wait for the utterance so the engine can provide a completion event.
      '-w',
      '-r',
      _mapCenteredValue(rate).toString(),
      '-p',
      _mapCenteredValue(pitch, center: 1.0, span: 1.0).toString(),
      '-i',
      _mapCenteredValue(volume, center: 0.5, span: 0.5).toString(),
      if (language != null && language.isNotEmpty) ...<String>['-l', language],
      if (voice != null) ...<String>['-y', voice],
      text,
    ];
    final process = await Process.start('spd-say', args);
    _activeProcess = process;
    // Drain both pipes while waiting so a verbose backend cannot block.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    final exitCode = await process.exitCode;
    if (identical(_activeProcess, process)) _activeProcess = null;
    if (exitCode != 0) {
      throw ProcessException(
          'spd-say', args, 'spd-say exited with $exitCode', exitCode);
    }
  }

  @override
  Future<void> stop() async {
    final process = _activeProcess;
    _activeProcess = null;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    try {
      // Speech Dispatcher keeps a queue outside this process; cancel it too.
      await Process.run('spd-say', <String>['-C']);
    } on ProcessException {
      // A disappearing backend is handled by the next probe/speak operation.
    }
  }

  @override
  void dispose() {
    _activeProcess?.kill(ProcessSignal.sigterm);
    _activeProcess = null;
  }

  bool _looksLikeLanguageTag(String value) =>
      RegExp(r'^[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]+)*$').hasMatch(value);

  String? _voiceForLanguage(String language) {
    final normalized = language.replaceAll('_', '-').toLowerCase();
    return _voicesByLanguage[normalized] ??
        _voicesByLanguage[normalized.split('-').first];
  }

  int _mapCenteredValue(
    double value, {
    double center = 0.5,
    double span = 0.5,
  }) {
    final normalized = ((value - center) / span * 100).round();
    return normalized.clamp(-100, 100);
  }
}
