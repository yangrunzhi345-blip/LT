import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/tts_real_model_validation.dart';

void main() {
  group('Enhanced TTS production model', () {
    test(
      'should install, load and synthesize the official model',
      () async {
        final rootPath = Platform.environment['LT_TTS_E2E_ROOT'];
        expect(rootPath, isNotNull,
            reason: 'Use a dedicated validation directory');
        final report = await validateRealTtsModel(
          root: Directory(rootPath!),
          allowDownload: Platform.environment['LT_TTS_ALLOW_DOWNLOAD'] == '1',
        );
        // ignore: avoid_print
        print(report);
        expect(report['generation'], 'NEURAL GENERATION VERIFIED');
        expect(report['multiSpeaker'], 'MULTI-SPEAKER VERIFIED');
      },
      skip: Platform.environment['LT_TTS_REAL_MODEL'] != '1',
      timeout: const Timeout(Duration(minutes: 15)),
    );
  });
}
