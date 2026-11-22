/// Persistence interface for lightweight setting cards.
///
/// Deliberately small: one document per card, listed, read, saved and soft
/// deleted. No tree, revision, trash or compression concepts exist here.
library;

import 'setting_card.dart';

abstract interface class SettingCardRepository {
  /// Cards of [kind] (all kinds when null), newest-updated first.
  ///
  /// Soft-deleted cards are excluded unless [includeDeleted] is true.
  Future<List<SettingCard>> list({
    SettingCardKind? kind,
    bool includeDeleted = false,
  });

  /// Reads one card by its stable [id], or null when it does not exist.
  Future<SettingCard?> findById(String id);

  /// Reads the card migrated from the legacy row [legacyId], if any.
  Future<SettingCard?> findLegacyId(String legacyId, {SettingCardKind? kind});

  /// Whether [id] already has a card (including soft-deleted ones).
  Future<bool> exists(String id);

  /// Inserts [card] only when [id] is absent; returns whether it was created.
  ///
  /// The compatibility migration uses this so re-running it can never overwrite
  /// a card the user has since edited.
  Future<bool> insertIfAbsent(SettingCard card);

  /// Inserts or updates the mutable fields of [card].
  Future<void> save(SettingCard card);

  /// Marks [id] deleted without removing the row.
  Future<void> softDelete(String id, {required String deletedAt});
}
