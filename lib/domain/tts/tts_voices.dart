/// Voice descriptors, device-local voice bindings and resolution targets.
///
/// Model / Speaker / Voice are intentionally decoupled:
/// - [TtsModelDescriptor] is the actual neural model.
/// - `speakerId` is an integer inside that model.
/// - [TtsVoiceDescriptor] is what LT shows and lets users bind.
/// - [VoiceBinding] maps a *stable resource id* to a `voiceId`.
///
/// Characters never store a model path or a speaker integer. They bind a
/// stable [VoiceBinding.voiceId]; the resolver turns it into
/// `voiceId -> modelId -> speakerId` at playback time.
library;

import 'tts_errors.dart';
import 'tts_models.dart';

/// A single voice exposed to users, backed by one speaker of one model.
class TtsVoiceDescriptor {
  const TtsVoiceDescriptor({
    required this.voiceId,
    required this.voiceFamily,
    required this.speakerId,
    required this.displayName,
    required this.languages,
    required this.capabilities,
  });

  /// Stable identifier users bind to. Encodes voice family + speaker, but is
  /// opaque to the UI and to resource content.
  final String voiceId;

  /// Shared family of compatible models that can provide this voice.
  final String voiceFamily;

  /// Integer speaker id inside the model.
  final int speakerId;

  /// Human display name (dynamic content; never an i18n key).
  final String displayName;

  /// Normalized BCP-47 language tags the voice can speak.
  final List<String> languages;

  final TtsVoiceCapabilities capabilities;
}

/// Device-local binding from a stable resource id to a voice.
///
/// This is a preference, not resource content: it must never be written into
/// `CharacterCardEditDraft`, `NpcEditDraft`, resource metadata or part text.
class VoiceBinding {
  const VoiceBinding({required this.resourceId, required this.voiceId});

  final String resourceId;
  final String voiceId;

  Map<String, Object?> toJson() => <String, Object?>{
        'resourceId': resourceId,
        'voiceId': voiceId,
      };

  static VoiceBinding? fromJson(Object? value) {
    if (value is! Map) return null;
    final resourceId = value['resourceId'];
    final voiceId = value['voiceId'];
    if (resourceId is! String || voiceId is! String) return null;
    if (resourceId.isEmpty || voiceId.isEmpty) return null;
    return VoiceBinding(resourceId: resourceId, voiceId: voiceId);
  }

  @override
  bool operator ==(Object other) =>
      other is VoiceBinding &&
      other.resourceId == resourceId &&
      other.voiceId == voiceId;

  @override
  int get hashCode => Object.hash(resourceId, voiceId);
}

/// Narrator is a first-class voice target, not a fake character resource.
class NarratorVoiceBinding {
  const NarratorVoiceBinding({required this.voiceId});

  final String voiceId;

  Map<String, Object?> toJson() => <String, Object?>{'voiceId': voiceId};

  static NarratorVoiceBinding? fromJson(Object? value) {
    if (value is! Map) return null;
    final voiceId = value['voiceId'];
    if (voiceId is! String || voiceId.isEmpty) return null;
    return NarratorVoiceBinding(voiceId: voiceId);
  }
}

/// All device-local neural TTS preferences, persisted as versioned JSON.
class TtsVoicePreferences {
  const TtsVoicePreferences({
    this.mode = TtsBackendKind.system,
    this.narratorVoiceId,
    this.defaultCharacterVoiceId,
    this.autoAssignVoices = true,
    this.bindingsByResourceId = const <String, String>{},
  });

  static const TtsVoicePreferences defaults = TtsVoicePreferences();

  /// Whether the user opted into the enhanced (neural) mode.
  final TtsBackendKind mode;

  /// Explicit narrator voice; null means "follow the global default" (system).
  final String? narratorVoiceId;

  /// Explicit default character voice; null means "auto assign".
  final String? defaultCharacterVoiceId;

  /// Whether unbound characters get a deterministic auto-assigned voice.
  final bool autoAssignVoices;

  /// resource id -> voiceId.
  final Map<String, String> bindingsByResourceId;

  bool get isNeuralEnabled => mode == TtsBackendKind.neural;

  String? bindingFor(String? resourceId) {
    if (resourceId == null) return null;
    return bindingsByResourceId[resourceId];
  }

  TtsVoicePreferences copyWith({
    TtsBackendKind? mode,
    String? narratorVoiceId,
    bool clearNarratorVoice = false,
    String? defaultCharacterVoiceId,
    bool clearDefaultCharacterVoice = false,
    bool? autoAssignVoices,
    Map<String, String>? bindingsByResourceId,
  }) {
    return TtsVoicePreferences(
      mode: mode ?? this.mode,
      narratorVoiceId:
          clearNarratorVoice ? null : (narratorVoiceId ?? this.narratorVoiceId),
      defaultCharacterVoiceId: clearDefaultCharacterVoice
          ? null
          : (defaultCharacterVoiceId ?? this.defaultCharacterVoiceId),
      autoAssignVoices: autoAssignVoices ?? this.autoAssignVoices,
      bindingsByResourceId: bindingsByResourceId ?? this.bindingsByResourceId,
    );
  }

  TtsVoicePreferences withBinding(String resourceId, String? voiceId) {
    final next = Map<String, String>.from(bindingsByResourceId);
    if (voiceId == null || voiceId.isEmpty) {
      next.remove(resourceId);
    } else {
      next[resourceId] = voiceId;
    }
    return copyWith(bindingsByResourceId: next);
  }
}

/// The concrete backend + voice a segment will be read with.
///
/// Resolution combines (in order): explicit per-request override, character
/// binding, narrator binding, default character voice, global default, model
/// default. Null targets mean "system TTS".
class ReadAloudVoiceTarget {
  const ReadAloudVoiceTarget({
    required this.backend,
    required this.capabilities,
    this.voiceId,
    this.modelId,
    this.speakerId,
    this.requestedLanguageTag,
  });

  /// System TTS fallback target.
  static const ReadAloudVoiceTarget system = ReadAloudVoiceTarget(
    backend: TtsBackendKind.system,
    capabilities: TtsVoiceCapabilities.system,
  );

  final TtsBackendKind backend;

  /// Null for the system backend.
  final String? voiceId;
  final String? modelId;
  final int? speakerId;

  final TtsVoiceCapabilities capabilities;

  /// Language requested for this segment (may be overridden by the model).
  final String? requestedLanguageTag;

  bool get isNeural => backend == TtsBackendKind.neural;

  @override
  String toString() => isNeural
      ? 'ReadAloudVoiceTarget(neural, $voiceId, speaker $speakerId)'
      : 'ReadAloudVoiceTarget(system)';
}

/// Throws a [TtsException] for the given [code] unless [condition] is true.
void requireTts(bool condition, TtsErrorCode code, [String? detail]) {
  if (!condition) throw TtsException(code, detail: detail);
}
