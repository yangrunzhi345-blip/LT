/// Catalog of officially verified, optionally downloadable neural TTS models.
///
/// Every URL, size and digest here was verified against the official
/// sherpa-onnx `tts-models` release. The catalog is intentionally explicit about
/// the (unknown) installed size: we do not guess numbers we have not measured.
///
/// Adding a future model family (VITS, Piper, ...) means adding a descriptor
/// and its voice list here; the rest of the pipeline is family-agnostic.
library;

import '../../domain/tts/tts_models.dart';
import '../../domain/tts/tts_voices.dart';

/// Well-known voice family for Kokoro multilingual v1.1.
const String kKokoroVoiceFamilyV11 = 'kokoro-v1_1';

/// Well-known voice family for Kokoro multilingual v1.0.
const String kKokoroVoiceFamilyV10 = 'kokoro-v1_0';

class TtsModelCatalog {
  TtsModelCatalog({List<TtsModelDescriptor>? models})
      : _models = models ?? _defaultModels;

  final List<TtsModelDescriptor> _models;

  List<TtsModelDescriptor> get models => List.unmodifiable(_models);

  TtsModelDescriptor? byId(String? modelId) {
    if (modelId == null) return null;
    for (final model in _models) {
      if (model.modelId == modelId) return model;
    }
    return null;
  }

  /// Voices of a model, derived from its `voiceFamily` + speaker count.
  List<TtsVoiceDescriptor> voicesForModel(TtsModelDescriptor model) =>
      voicesForFamily(model.voiceFamily, model.speakerCount);

  /// Finds a compatible model, preferring installed FP32 over INT8 v1.1.
  ///
  /// [isInstalled] lets the caller prefer an installed model when several
  /// quantizations of the same family are present.
  TtsModelDescriptor? modelForVoice(
    String voiceId, {
    bool Function(TtsModelDescriptor model)? isInstalled,
  }) {
    final voice = voiceById(voiceId);
    if (voice == null) return null;
    final candidates = _models
        .where((model) =>
            model.voiceFamily == voice.voiceFamily &&
            model.speakerCount > voice.speakerId)
        .toList()
      ..sort((a, b) {
        final priority = _modelPriority(a.modelId).compareTo(
          _modelPriority(b.modelId),
        );
        return priority != 0 ? priority : a.modelId.compareTo(b.modelId);
      });
    if (candidates.isEmpty) return null;
    if (isInstalled != null) {
      for (final candidate in candidates) {
        if (isInstalled(candidate)) return candidate;
      }
    }
    return candidates.first;
  }

  TtsVoiceDescriptor? voiceById(String voiceId) {
    for (final model in _models) {
      final match = RegExp('^${RegExp.escape(model.voiceFamily)}:s([0-9]+)\$')
          .firstMatch(voiceId);
      if (match != null) {
        final sid = int.tryParse(match.group(1)!);
        if (sid == null || sid < 0 || sid >= model.speakerCount) continue;
        return _buildVoice(model, sid);
      }
    }
    return null;
  }

  // Compatible quantizations keep the same voices; installing INT8 must not
  // silently replace an already installed full-precision model. Other families
  // have a stable id tie-break until their compatibility policy is defined.
  static int _modelPriority(String modelId) => switch (modelId) {
        'kokoro-multi-lang-v1_1' => 0,
        'kokoro-int8-multi-lang-v1_1' => 1,
        _ => 2,
      };

  List<TtsVoiceDescriptor> allVoices() {
    final seen = <String>{};
    final voices = <TtsVoiceDescriptor>[];
    for (final model in _models) {
      for (final voice in voicesForModel(model)) {
        if (seen.add(voice.voiceId)) voices.add(voice);
      }
    }
    return voices;
  }

  List<TtsVoiceDescriptor> voicesForFamily(String voiceFamily, int count) {
    final model = _modelForFamily(voiceFamily);
    if (model == null) return const <TtsVoiceDescriptor>[];
    final result = <TtsVoiceDescriptor>[];
    for (var sid = 0; sid < count; sid++) {
      result.add(_buildVoice(model, sid));
    }
    return result;
  }

  TtsModelDescriptor? _modelForFamily(String voiceFamily) {
    for (final model in _models) {
      if (model.voiceFamily == voiceFamily) return model;
    }
    return null;
  }

  TtsVoiceDescriptor _buildVoice(TtsModelDescriptor model, int sid) {
    final names = _speakerNames[model.voiceFamily];
    final name =
        (names != null && sid < names.length) ? names[sid] : 'speaker_$sid';
    return TtsVoiceDescriptor(
      voiceId: '${model.voiceFamily}:s$sid',
      voiceFamily: model.voiceFamily,
      speakerId: sid,
      displayName: name,
      languages: _speakerLanguages(model.voiceFamily, name),
      capabilities: model.capabilities,
    );
  }

  /// Maps a voice entirely from its official speaker prefix.
  static List<String> _speakerLanguages(String family, String name) {
    if (family == kKokoroVoiceFamilyV10) return const <String>['en-US'];
    if (name.startsWith('af_') || name.startsWith('am_')) {
      return const <String>['en-US'];
    }
    if (name.startsWith('bf_') || name.startsWith('bm_')) {
      return const <String>['en-GB'];
    }
    if (name.startsWith('zf_') || name.startsWith('zm_')) {
      return const <String>['zh-CN'];
    }
    return const <String>['zh-CN'];
  }

  /// Official speaker names, in speaker-id order (0-based).
  ///
  /// Transcribed from the official sherpa-onnx docs for
  /// `kokoro-multi-lang-v1_1` (103 speakers). Kept as data so the mapping is
  /// auditable and stable.
  static const Map<String, List<String>> _speakerNames = <String, List<String>>{
    kKokoroVoiceFamilyV11: <String>[
      'af_maple',
      'af_sol',
      'bf_vale',
      'zf_001',
      'zf_002',
      'zf_003',
      'zf_004',
      'zf_005',
      'zf_006',
      'zf_007',
      'zf_008',
      'zf_017',
      'zf_018',
      'zf_019',
      'zf_021',
      'zf_022',
      'zf_023',
      'zf_024',
      'zf_026',
      'zf_027',
      'zf_028',
      'zf_032',
      'zf_036',
      'zf_038',
      'zf_039',
      'zf_040',
      'zf_042',
      'zf_043',
      'zf_044',
      'zf_046',
      'zf_047',
      'zf_048',
      'zf_049',
      'zf_051',
      'zf_059',
      'zf_060',
      'zf_067',
      'zf_070',
      'zf_071',
      'zf_072',
      'zf_073',
      'zf_074',
      'zf_075',
      'zf_076',
      'zf_077',
      'zf_078',
      'zf_079',
      'zf_083',
      'zf_084',
      'zf_085',
      'zf_086',
      'zf_087',
      'zf_088',
      'zf_090',
      'zf_092',
      'zf_093',
      'zf_094',
      'zf_099',
      'zm_009',
      'zm_010',
      'zm_011',
      'zm_012',
      'zm_013',
      'zm_014',
      'zm_015',
      'zm_016',
      'zm_020',
      'zm_025',
      'zm_029',
      'zm_030',
      'zm_031',
      'zm_033',
      'zm_034',
      'zm_035',
      'zm_037',
      'zm_041',
      'zm_045',
      'zm_050',
      'zm_052',
      'zm_053',
      'zm_054',
      'zm_055',
      'zm_056',
      'zm_057',
      'zm_058',
      'zm_061',
      'zm_062',
      'zm_063',
      'zm_064',
      'zm_065',
      'zm_066',
      'zm_068',
      'zm_069',
      'zm_080',
      'zm_081',
      'zm_082',
      'zm_089',
      'zm_091',
      'zm_095',
      'zm_096',
      'zm_097',
      'zm_098',
      'zm_100',
    ],
    // v1.0 uses 53 anonymous speakers; we only expose the count and keep the
    // names synthetic so identity remains stable. This model is not offered for
    // download in this release; it exists to keep the abstraction honest.
    kKokoroVoiceFamilyV10: <String>[
      'af_alloy',
      'af_aoede',
      'af_bella',
      'af_heart',
    ],
  };

  static const String _kokoroLicense = 'Apache-2.0';
  static final Uri _kokoroLicenseUri =
      Uri.parse('https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh');

  static final List<TtsModelDescriptor> _defaultModels = <TtsModelDescriptor>[
    TtsModelDescriptor(
      modelId: 'kokoro-int8-multi-lang-v1_1',
      version: 'v1_1',
      displayName: 'Kokoro v1.1 (INT8)',
      engineFamily: 'kokoro',
      voiceFamily: kKokoroVoiceFamilyV11,
      languages: const <String>['zh-CN', 'en-US'],
      speakerCount: 103,
      downloadUri: Uri.parse(
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'kokoro-int8-multi-lang-v1_1.tar.bz2',
      ),
      downloadSizeBytes: 147031220,
      license: _kokoroLicense,
      licenseUri: _kokoroLicenseUri,
      archiveFormat: TtsArchiveFormat.tarBz2,
      requiredFiles: const <TtsFileSpec>[
        TtsFileSpec(name: 'voices.bin'),
        TtsFileSpec(name: 'tokens.txt'),
        TtsFileSpec(name: 'espeak-ng-data'),
      ],
      modelFileName: const <String>['model.int8.onnx'],
      lexiconFileNames: const <String>[
        'lexicon-us-en.txt',
        'lexicon-zh.txt',
      ],
      capabilities: TtsVoiceCapabilities.kokoro,
      integrity: const TtsModelIntegrity.officialSha256(
        'a1e94694776049035c4f2c6529f003aaece993c76aae9a78995831c3c4dcafc6',
      ),
    ),
    TtsModelDescriptor(
      modelId: 'kokoro-multi-lang-v1_1',
      version: 'v1_1',
      displayName: 'Kokoro v1.1 (FP32)',
      engineFamily: 'kokoro',
      voiceFamily: kKokoroVoiceFamilyV11,
      languages: const <String>['zh-CN', 'en-US'],
      speakerCount: 103,
      downloadUri: Uri.parse(
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'kokoro-multi-lang-v1_1.tar.bz2',
      ),
      downloadSizeBytes: 364816464,
      license: _kokoroLicense,
      licenseUri: _kokoroLicenseUri,
      archiveFormat: TtsArchiveFormat.tarBz2,
      requiredFiles: const <TtsFileSpec>[
        TtsFileSpec(name: 'voices.bin'),
        TtsFileSpec(name: 'tokens.txt'),
        TtsFileSpec(name: 'espeak-ng-data'),
      ],
      modelFileName: const <String>['model.onnx'],
      lexiconFileNames: const <String>[
        'lexicon-us-en.txt',
        'lexicon-zh.txt',
      ],
      capabilities: TtsVoiceCapabilities.kokoro,
      integrity: const TtsModelIntegrity.officialSha256(
        'a3f4c73d043860e3fd2e5b06f36795eb81de0fc8e8de6df703245edddd87dbad',
      ),
    ),
  ];
}
