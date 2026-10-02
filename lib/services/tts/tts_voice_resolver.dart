import '../../domain/tts/speech_plan.dart';
import '../../domain/tts/tts_errors.dart';
import '../../domain/tts/tts_models.dart';
import '../../domain/tts/tts_voices.dart';
import 'tts_model_catalog.dart';
import 'tts_voice_assignment.dart';
import 'tts_voice_binding_store.dart';

/// Read-only view of what is installed, used by the resolver.
abstract class TtsInstalledModelRegistry {
  bool isModelInstalled(String modelId);

  List<TtsModelDescriptor> get installedModelDescriptors;
}

/// Outcome of resolving the voice for a segment.
class TtsVoiceResolution {
  const TtsVoiceResolution.system()
      : target = null,
        fallback = false,
        errorCode = null;

  const TtsVoiceResolution.neural(ReadAloudVoiceTarget this.target)
      : fallback = false,
        errorCode = null;

  const TtsVoiceResolution.unavailable(TtsErrorCode this.errorCode)
      : target = null,
        fallback = true;

  /// Null means the system backend should be used.
  final ReadAloudVoiceTarget? target;

  /// True when a neural voice was requested but could not be served.
  final bool fallback;

  final TtsErrorCode? errorCode;

  bool get isSystem => target == null;
}

/// Resolves `resource id / role -> concrete voice target`.
///
/// Resolution order: explicit per-resource binding, default character voice,
/// deterministic auto assignment (when enabled), narrator binding, then system
/// TTS. Narrator is the fallback for anything that cannot be confidently
/// attributed — we never guess a character.
class TtsVoiceResolver {
  TtsVoiceResolver({
    required TtsModelCatalog catalog,
    required TtsVoiceBindingStore bindings,
    required TtsInstalledModelRegistry registry,
    TtsVoiceAssignment assignment = const TtsVoiceAssignment(),
  })  : _catalog = catalog,
        _bindings = bindings,
        _registry = registry,
        _assignment = assignment;

  final TtsModelCatalog _catalog;
  final TtsVoiceBindingStore _bindings;
  final TtsInstalledModelRegistry _registry;
  final TtsVoiceAssignment _assignment;

  Map<String, String> _sessionAssignments = <String, String>{};

  /// Prepares deterministic auto assignments for all speakers of a plan.
  ///
  /// Collision avoidance is applied across the whole plan, so two co-occurring
  /// characters do not accidentally share a voice.
  void beginSession(Iterable<String> speakerResourceIds) {
    _sessionAssignments = <String, String>{};
    if (!_bindings.preferences.isNeuralEnabled ||
        !_bindings.preferences.autoAssignVoices) {
      return;
    }
    final pool = voicePool();
    if (pool.isEmpty) return;
    _sessionAssignments = _assignment.assignForPlan(
      speakerResourceIds.where((id) => id.isNotEmpty),
      pool,
    );
  }

  /// Installed voices available for auto assignment, in deterministic order.
  List<TtsVoiceDescriptor> voicePool() {
    final models = List<TtsModelDescriptor>.from(
      _registry.installedModelDescriptors,
    )..sort((a, b) => a.modelId.compareTo(b.modelId));
    final seen = <String>{};
    final pool = <TtsVoiceDescriptor>[];
    for (final model in models) {
      for (final voice in _catalog.voicesForModel(model)) {
        if (seen.add(voice.voiceId)) pool.add(voice);
      }
    }
    return pool;
  }

  /// Resolves the target for one segment.
  TtsVoiceResolution resolve({
    required SpeechRole role,
    String? speakerResourceId,
  }) {
    final prefs = _bindings.preferences;
    if (!prefs.isNeuralEnabled) return const TtsVoiceResolution.system();

    final voiceId = _voiceIdFor(
      role: role,
      speakerResourceId: speakerResourceId,
    );
    if (voiceId == null || voiceId.isEmpty) {
      // No neural voice configured for this role: narrator/system handles it.
      return const TtsVoiceResolution.system();
    }

    final model = _catalog.modelForVoice(
      voiceId,
      isInstalled: (candidate) => _registry.isModelInstalled(candidate.modelId),
    );
    final voice = _catalog.voiceById(voiceId);
    if (model == null || voice == null) {
      return const TtsVoiceResolution.unavailable(
          TtsErrorCode.voiceUnavailable);
    }
    if (!_registry.isModelInstalled(model.modelId)) {
      return const TtsVoiceResolution.unavailable(
        TtsErrorCode.modelUnavailable,
      );
    }
    return TtsVoiceResolution.neural(
      ReadAloudVoiceTarget(
        backend: TtsBackendKind.neural,
        capabilities: model.capabilities,
        voiceId: voice.voiceId,
        modelId: model.modelId,
        speakerId: voice.speakerId,
      ),
    );
  }

  String? _voiceIdFor({
    required SpeechRole role,
    String? speakerResourceId,
  }) {
    final prefs = _bindings.preferences;
    final isNarrator = role != SpeechRole.dialogue ||
        speakerResourceId == null ||
        speakerResourceId.isEmpty;
    if (isNarrator) return prefs.narratorVoiceId;

    final explicit = prefs.bindingFor(speakerResourceId);
    if (explicit != null) return explicit;

    if (prefs.defaultCharacterVoiceId != null) {
      return prefs.defaultCharacterVoiceId;
    }
    if (prefs.autoAssignVoices) {
      return _sessionAssignments[speakerResourceId];
    }
    return prefs.narratorVoiceId;
  }
}
