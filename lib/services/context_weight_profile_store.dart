import '../application/narrative/context_weighting.dart';
import 'repositories/settings_repository.dart';

/// Settings KV authority for the narrative context profile.
final class ContextWeightProfileStore {
  static const settingKey = 'narrative_context_weight_profile';
  final ISettingsRepository _repository;

  const ContextWeightProfileStore(this._repository);

  Future<ContextWeightProfile> load() async {
    final value = await _repository.getSetting(settingKey);
    return value == null
        ? ContextWeightPresets.balanced
        : ContextWeightProfile.decode(value);
  }

  Future<void> save(ContextWeightProfile profile) =>
      _repository.setSetting(settingKey, profile.encode());
}
