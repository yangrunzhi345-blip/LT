import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/domain/tts/tts_voices.dart';
import 'package:lt_dialogue/services/repositories/settings_repository.dart';
import 'package:lt_dialogue/services/tts/tts_voice_binding_store.dart';

class _MemorySettingsRepository implements ISettingsRepository {
  final Map<String, String> values = <String, String>{};

  @override
  Future<Map<String, String>> getAllSettings() async =>
      Map<String, String>.from(values);

  @override
  Future<void> setSettings(Map<String, String> input) async {
    values.addAll(input);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('missing keys fall back to system mode defaults', () {
    final prefs = parseTtsVoicePreferences(const <String, String>{});
    expect(prefs.mode, TtsBackendKind.system);
    expect(prefs.isNeuralEnabled, isFalse);
    expect(prefs.narratorVoiceId, isNull);
    expect(prefs.defaultCharacterVoiceId, isNull);
    expect(prefs.autoAssignVoices, isTrue);
    expect(prefs.bindingsByResourceId, isEmpty);
  });

  test('malformed JSON is safely ignored', () {
    final prefs = parseTtsVoicePreferences(<String, String>{
      TtsVoiceSettingKeys.preferences: '{not json',
      TtsVoiceSettingKeys.bindings: 'also bad',
      TtsVoiceSettingKeys.narrator: '[1,2,3]',
    });
    expect(prefs.mode, TtsBackendKind.system);
    expect(prefs.narratorVoiceId, isNull);
    expect(prefs.bindingsByResourceId, isEmpty);
  });

  test('unknown mode names degrade to system', () {
    final prefs = parseTtsVoicePreferences(<String, String>{
      TtsVoiceSettingKeys.preferences:
          '{"schema":1,"mode":"quantum","autoAssignVoices":false}',
    });
    expect(prefs.mode, TtsBackendKind.system);
    expect(prefs.autoAssignVoices, isFalse);
  });

  test('valid bindings round-trip through the settings store', () async {
    final repo = _MemorySettingsRepository();
    final store = SettingsRepoTtsVoiceStore(repo);
    const original = TtsVoicePreferences(
      mode: TtsBackendKind.neural,
      narratorVoiceId: 'family:s1',
      defaultCharacterVoiceId: 'family:s2',
      autoAssignVoices: false,
      bindingsByResourceId: <String, String>{
        'char-lin': 'family:s3',
        'npc-1': 'family:s4',
      },
    );

    await store.save(original);
    final restored = parseTtsVoicePreferences(repo.values);

    expect(restored.mode, TtsBackendKind.neural);
    expect(restored.narratorVoiceId, 'family:s1');
    expect(restored.defaultCharacterVoiceId, 'family:s2');
    expect(restored.autoAssignVoices, isFalse);
    expect(restored.bindingsByResourceId['char-lin'], 'family:s3');
    expect(restored.bindingsByResourceId['npc-1'], 'family:s4');
  });

  test('store notifications update memory before persistence', () async {
    final repo = _MemorySettingsRepository();
    final store = TtsVoiceBindingStore(store: SettingsRepoTtsVoiceStore(repo));
    var notifications = 0;
    store.addListener(() => notifications++);

    await store.setBinding('char-lin', 'family:s9');

    expect(store.preferences.bindingFor('char-lin'), 'family:s9');
    expect(notifications, greaterThan(0));
    expect(repo.values[TtsVoiceSettingKeys.bindings], contains('char-lin'));
  });

  test('clearing a binding keeps other bindings', () async {
    final store = TtsVoiceBindingStore(
      initial: const TtsVoicePreferences(
        bindingsByResourceId: <String, String>{
          'a': 'family:s1',
          'b': 'family:s2',
        },
      ),
    );
    await store.clearBinding('a');
    expect(store.preferences.bindingFor('a'), isNull);
    expect(store.preferences.bindingFor('b'), 'family:s2');
  });
}
