import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../domain/tts/tts_models.dart';
import '../../domain/tts/tts_voices.dart';
import '../repositories/settings_repository.dart';

/// Settings KV keys for the device-local neural voice configuration.
///
/// These are preferences, not resource content: they must never be written into
/// a character/NPC draft, resource metadata or part text.
class TtsVoiceSettingKeys {
  const TtsVoiceSettingKeys._();

  static const String bindings = 'tts_voice_bindings_v1';
  static const String narrator = 'tts_narrator_voice_binding_v1';
  static const String defaultCharacter = 'tts_default_character_voice_v1';
  static const String preferences = 'tts_neural_preferences_v1';
}

/// Parses the neural voice preferences from an already-loaded settings map.
///
/// Every field falls back safely to its default when the JSON is missing,
/// malformed or from a newer schema, so a broken value can never break startup
/// or discard the user's other settings.
TtsVoicePreferences parseTtsVoicePreferences(Map<String, String> values) {
  const defaults = TtsVoicePreferences.defaults;
  var mode = defaults.mode;
  var autoAssign = defaults.autoAssignVoices;

  final rawPrefs = values[TtsVoiceSettingKeys.preferences];
  if (rawPrefs != null) {
    final decoded = _decodeMap(rawPrefs);
    if (decoded != null) {
      final modeName = decoded['mode'];
      if (modeName is String) {
        mode = modeName == TtsBackendKind.neural.name
            ? TtsBackendKind.neural
            : TtsBackendKind.system;
      }
      final auto = decoded['autoAssignVoices'];
      if (auto is bool) autoAssign = auto;
    }
  }

  final bindings = <String, String>{};
  final rawBindings = values[TtsVoiceSettingKeys.bindings];
  if (rawBindings != null) {
    final decoded = _decodeMap(rawBindings);
    final map = decoded?['bindings'];
    if (map is Map) {
      for (final entry in map.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is String && value is String) {
          final binding = VoiceBinding.fromJson(
            <String, Object?>{'resourceId': key, 'voiceId': value},
          );
          if (binding != null) {
            bindings[binding.resourceId] = binding.voiceId;
          }
        }
      }
    }
  }

  final narrator = NarratorVoiceBinding.fromJson(
    _decodeMap(values[TtsVoiceSettingKeys.narrator] ?? ''),
  );
  final defaultCharacter = NarratorVoiceBinding.fromJson(
    _decodeMap(values[TtsVoiceSettingKeys.defaultCharacter] ?? ''),
  );

  return TtsVoicePreferences(
    mode: mode,
    narratorVoiceId: narrator?.voiceId,
    defaultCharacterVoiceId: defaultCharacter?.voiceId,
    autoAssignVoices: autoAssign,
    bindingsByResourceId: bindings,
  );
}

Map<String, Object?>? _decodeMap(String raw) {
  if (raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return <String, Object?>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
  } catch (_) {
    // Malformed value: fall back to defaults.
  }
  return null;
}

/// Persistence port for neural voice preferences.
abstract class TtsVoicePreferencesStore {
  Future<void> save(TtsVoicePreferences preferences);
}

/// [ISettingsRepository] backed implementation. No schema change is required:
/// everything is stored in the existing `settings` KV table.
class SettingsRepoTtsVoiceStore implements TtsVoicePreferencesStore {
  SettingsRepoTtsVoiceStore(this._repository);

  final ISettingsRepository _repository;

  @override
  Future<void> save(TtsVoicePreferences preferences) async {
    await _repository.setSettings(<String, String>{
      TtsVoiceSettingKeys.preferences: jsonEncode(<String, Object?>{
        'schema': 1,
        'mode': preferences.mode.name,
        'autoAssignVoices': preferences.autoAssignVoices,
      }),
      TtsVoiceSettingKeys.bindings: jsonEncode(<String, Object?>{
        'schema': 1,
        'bindings': preferences.bindingsByResourceId,
      }),
      TtsVoiceSettingKeys.narrator: jsonEncode(<String, Object?>{
        'schema': 1,
        'voiceId': preferences.narratorVoiceId ?? '',
      }),
      TtsVoiceSettingKeys.defaultCharacter: jsonEncode(<String, Object?>{
        'schema': 1,
        'voiceId': preferences.defaultCharacterVoiceId ?? '',
      }),
    });
  }
}

/// In-memory single source of truth for the team's voice configuration.
///
/// Playback reads it synchronously; writes update memory immediately and persist
/// asynchronously. Load it once from [parseTtsVoicePreferences] at startup.
class TtsVoiceBindingStore extends ChangeNotifier {
  TtsVoiceBindingStore({
    TtsVoicePreferences initial = TtsVoicePreferences.defaults,
    TtsVoicePreferencesStore? store,
  })  : _preferences = initial,
        _store = store;

  final TtsVoicePreferencesStore? _store;
  TtsVoicePreferences _preferences;

  TtsVoicePreferences get preferences => _preferences;

  bool get isNeuralEnabled => _preferences.isNeuralEnabled;

  /// Replaces the in-memory state without touching storage (startup restore).
  void restore(TtsVoicePreferences preferences) {
    _preferences = preferences;
    notifyListeners();
  }

  Future<void> setMode(TtsBackendKind mode) =>
      _update(_preferences.copyWith(mode: mode));

  Future<void> setNarratorVoice(String? voiceId) => _update(
        voiceId == null || voiceId.isEmpty
            ? _preferences.copyWith(clearNarratorVoice: true)
            : _preferences.copyWith(narratorVoiceId: voiceId),
      );

  Future<void> setDefaultCharacterVoice(String? voiceId) => _update(
        voiceId == null || voiceId.isEmpty
            ? _preferences.copyWith(clearDefaultCharacterVoice: true)
            : _preferences.copyWith(defaultCharacterVoiceId: voiceId),
      );

  Future<void> setAutoAssignVoices(bool value) =>
      _update(_preferences.copyWith(autoAssignVoices: value));

  Future<void> setBinding(String resourceId, String? voiceId) =>
      _update(_preferences.withBinding(resourceId, voiceId));

  Future<void> clearBinding(String resourceId) =>
      _update(_preferences.withBinding(resourceId, null));

  Future<void> _update(TtsVoicePreferences next) async {
    _preferences = next;
    notifyListeners();
    final store = _store;
    if (store == null) return;
    try {
      await store.save(next);
    } catch (error) {
      debugPrint('[TtsVoice] 偏好写入失败: $error');
    }
  }
}
