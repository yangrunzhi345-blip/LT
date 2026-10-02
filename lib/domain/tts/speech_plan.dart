/// Speech planning contracts: who says what within a narrative text.
///
/// The planner is pure Dart and never calls an LLM. When it cannot reliably
/// attribute a piece of dialogue to a known speaker it falls back to narration
/// rather than guessing a character.
library;

/// Role of a speech segment.
enum SpeechRole {
  narration,
  dialogue,

  /// Could not be classified reliably; read as narration.
  unknown,
}

/// One planned speech unit, before length-based segmentation.
class SpeechSegment {
  const SpeechSegment({
    required this.id,
    required this.text,
    required this.role,
    this.speakerResourceId,
    this.confidence = 0,
    this.languageTag,
  });

  final String id;
  final String text;
  final SpeechRole role;

  /// Stable resource id of the attributed speaker, when known.
  final String? speakerResourceId;

  /// 0..1 confidence of the attribution. Only high-confidence attributions are
  /// bound to a character.
  final double confidence;

  final String? languageTag;

  bool get isDialogue => role == SpeechRole.dialogue;

  SpeechSegment copyWith({
    String? text,
    SpeechRole? role,
    String? speakerResourceId,
    double? confidence,
    String? languageTag,
  }) {
    return SpeechSegment(
      id: id,
      text: text ?? this.text,
      role: role ?? this.role,
      speakerResourceId: speakerResourceId ?? this.speakerResourceId,
      confidence: confidence ?? this.confidence,
      languageTag: languageTag ?? this.languageTag,
    );
  }
}

/// The complete plan for one source of narrative text.
class SpeechPlan {
  const SpeechPlan({required this.segments});

  static const SpeechPlan empty = SpeechPlan(segments: <SpeechSegment>[]);

  final List<SpeechSegment> segments;

  bool get isEmpty => segments.isEmpty;
  int get length => segments.length;

  /// Unique speaker resource ids referenced by dialogue segments.
  List<String> get speakerResourceIds {
    final ids = <String>[];
    for (final segment in segments) {
      final id = segment.speakerResourceId;
      if (segment.isDialogue && id != null && !ids.contains(id)) {
        ids.add(id);
      }
    }
    return ids;
  }
}

/// A known speaker the planner may attribute dialogue to.
class NarrativeSpeakerRef {
  const NarrativeSpeakerRef({
    required this.resourceId,
    required this.displayName,
    this.aliases = const <String>[],
    this.resourceType,
  });

  /// Stable resource id. Never derive a binding from [displayName].
  final String resourceId;

  final String displayName;

  /// Optional aliases / nicknames (only when the resource structure has them).
  final List<String> aliases;

  final String? resourceType;

  /// All names this speaker may be referred to by, longest first so that
  /// "陈默老师" matches before "陈默".
  List<String> get names {
    final all = <String>{
      if (displayName.trim().isNotEmpty) displayName.trim(),
      for (final alias in aliases)
        if (alias.trim().isNotEmpty) alias.trim(),
    }.toList();
    all.sort((a, b) => b.length.compareTo(a.length));
    return all;
  }

  /// Whether [candidate] names this speaker.
  bool matches(String candidate) {
    final value = candidate.trim();
    if (value.isEmpty) return false;
    return names.contains(value);
  }
}

/// Immutable projection of the currently known speakers of a scene.
///
/// Built by the Adventure / Resource layer and passed into the read-aloud
/// authority as *data*, so the planner never depends on Providers or SQLite.
class NarrativeSpeakerContext {
  const NarrativeSpeakerContext({required this.speakers});

  const NarrativeSpeakerContext.empty()
      : speakers = const <NarrativeSpeakerRef>[];

  final List<NarrativeSpeakerRef> speakers;

  bool get isEmpty => speakers.isEmpty;

  /// Longest name first, so substring collisions resolve to the specific name.
  List<NarrativeSpeakerRef> get byNameLength {
    final sorted = List<NarrativeSpeakerRef>.from(speakers);
    sorted.sort((a, b) {
      final aLongest = a.names.isEmpty ? 0 : a.names.first.length;
      final bLongest = b.names.isEmpty ? 0 : b.names.first.length;
      return bLongest.compareTo(aLongest);
    });
    return sorted;
  }

  NarrativeSpeakerRef? byResourceId(String? resourceId) {
    if (resourceId == null) return null;
    for (final speaker in speakers) {
      if (speaker.resourceId == resourceId) return speaker;
    }
    return null;
  }
}
