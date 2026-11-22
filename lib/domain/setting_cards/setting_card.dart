/// Lightweight single-document setting cards.
///
/// Phase 5 replaces the `Resource -> Section -> Part` editing IDE with one
/// markdown/JSON document per worldview, character or NPC. A card keeps only
/// what the lightweight editor and the adventure snapshot need: identity,
/// classification, a single body, and a small map of runtime metadata.
///
/// The model is deliberately independent from `domain/resources`: the heavy
/// tree is being retired, so new code must not spread a dependency on it.
library;

/// What a card describes.
///
/// Storage values intentionally match the legacy `resources.type` values so the
/// compatibility migration can map old rows without inventing a second
/// vocabulary.
enum SettingCardKind {
  worldview('worldview'),
  character('character'),
  npc('npc');

  const SettingCardKind(this.storageValue);

  /// Stable value used by storage.
  final String storageValue;

  /// Parses [storageValue]; unknown input is rejected instead of defaulted so a
  /// typo cannot silently create a card of the wrong kind.
  static SettingCardKind fromStorageValue(String? value) {
    for (final kind in SettingCardKind.values) {
      if (kind.storageValue == value) return kind;
    }
    throw ArgumentError.value(value, 'value', 'Unknown setting card kind');
  }
}

/// Editorial state of a card.
enum SettingCardStatus {
  draft,
  confirmed,
  archived;

  String get storageValue => name;

  /// Historical rows may carry an unknown status; those degrade to [draft]
  /// rather than failing the whole library read.
  static SettingCardStatus fromStorageValue(String? value) {
    for (final status in SettingCardStatus.values) {
      if (status.storageValue == value) return status;
    }
    return SettingCardStatus.draft;
  }
}

/// Where a card came from.
///
/// Only used for diagnostics and for the one-time compatibility migration; the
/// editor treats every card the same.
enum SettingCardOrigin {
  /// Created directly with the lightweight editor.
  native('native'),

  /// Merged from an existing unified resource tree.
  legacyTree('legacy_tree'),

  /// Recovered from a legacy table row that has no usable tree.
  legacyRow('legacy_row');

  const SettingCardOrigin(this.storageValue);

  final String storageValue;

  static SettingCardOrigin fromStorageValue(String? value) {
    for (final origin in SettingCardOrigin.values) {
      if (origin.storageValue == value) return origin;
    }
    return SettingCardOrigin.native;
  }
}

/// One editable setting document.
final class SettingCard {
  const SettingCard({
    required this.id,
    required this.kind,
    required this.name,
    this.summary = '',
    this.content = '',
    this.status = SettingCardStatus.draft,
    this.origin = SettingCardOrigin.native,
    this.mode = '',
    this.originWorldviewId = '',
    this.metadata = const <String, Object?>{},
    this.legacyId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// Stable identity. For migrated rows this keeps the unified resource id so
  /// relationships and adventure snapshots that already reference it keep
  /// working.
  final String id;

  final SettingCardKind kind;
  final String name;
  final String summary;

  /// The whole document body (markdown or JSON-as-text). This is the only place
  /// body text lives.
  final String content;

  final SettingCardStatus status;
  final SettingCardOrigin origin;

  /// Library mode (conversation / adventure / creation); empty when the source
  /// never had one.
  final String mode;

  /// Native worldview identity a character/NPC belongs to, when known.
  final String originWorldviewId;

  /// Small runtime metadata only: provenance, source, tags. Never body text.
  final Map<String, Object?> metadata;

  /// Raw id of the legacy table row this card was migrated from.
  final String? legacyId;

  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  bool get isDeleted => deletedAt != null;

  SettingCard copyWith({
    String? name,
    String? summary,
    String? content,
    SettingCardStatus? status,
    String? mode,
    String? originWorldviewId,
    Map<String, Object?>? metadata,
    String? updatedAt,
    String? deletedAt,
  }) {
    return SettingCard(
      id: id,
      kind: kind,
      name: name ?? this.name,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      status: status ?? this.status,
      origin: origin,
      mode: mode ?? this.mode,
      originWorldviewId: originWorldviewId ?? this.originWorldviewId,
      metadata: metadata ?? this.metadata,
      legacyId: legacyId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  /// Compact diagnostic form. Body text is never included.
  @override
  String toString() {
    final kindValue = kind.storageValue;
    final charCount = content.length;
    return 'SettingCard($id, $kindValue, "$name", $charCount chars)';
  }
}
