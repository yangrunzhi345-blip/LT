/// Status of a blueprint in its lifecycle.
///
/// Only the enum survives: the card-backed library no longer plans or
/// validates blueprints, but the authorized-budget reader still compares
/// persisted `resource_blueprints.status` against `confirmed`.
enum BlueprintStatus {
  draft,
  confirmed,
  superseded,
  cancelled;

  String get storageValue => name;

  static BlueprintStatus fromStorage(String? value) {
    for (final status in BlueprintStatus.values) {
      if (status.storageValue == value) return status;
    }
    return BlueprintStatus.draft;
  }
}
