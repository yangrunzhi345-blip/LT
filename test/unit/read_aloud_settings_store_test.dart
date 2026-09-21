import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/read_aloud/read_aloud_contracts.dart';
import 'package:lt_dialogue/services/read_aloud/read_aloud_settings_store.dart';
import 'package:lt_dialogue/services/repositories/settings_repository.dart';

class _MemorySettingsRepository implements ISettingsRepository {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> setSettings(Map<String, String> incoming) async {
    values.addAll(incoming);
  }

  @override
  Future<String?> getSetting(String key) async => values[key];

  @override
  Future<void> setSetting(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<Map<String, String>> getAllSettings() async =>
      Map<String, String>.of(values);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ReadAloudPreferences 解析', () {
    test('save 写入稳定的 settings KV 键', () async {
      final repo = _MemorySettingsRepository();
      final store = SettingsRepoReadAloudStore(repo);

      await store.save(
        const ReadAloudPreferences(
          enabled: true,
          autoRead: true,
          rate: 0.75,
          pitch: 1.25,
          volume: 0.4,
        ),
      );

      expect(repo.values[ReadAloudSettingKeys.enabled], '1');
      expect(repo.values[ReadAloudSettingKeys.autoRead], '1');
      expect(repo.values[ReadAloudSettingKeys.rate], '0.75');
      expect(repo.values[ReadAloudSettingKeys.pitch], '1.25');
      expect(repo.values[ReadAloudSettingKeys.volume], '0.4');
    });

    test('解析往返一致（复现 SettingsProvider 启动恢复路径）', () async {
      final repo = _MemorySettingsRepository();
      final store = SettingsRepoReadAloudStore(repo);

      const original = ReadAloudPreferences(
        enabled: true,
        autoRead: false,
        rate: 0.3,
        pitch: 0.8,
        volume: 1.0,
      );
      await store.save(original);
      final restored = parseReadAloudPreferences(await repo.getAllSettings());

      expect(restored.enabled, isTrue);
      expect(restored.autoRead, isFalse);
      expect(restored.rate, 0.3);
      expect(restored.pitch, 0.8);
      expect(restored.volume, 1.0);
    });

    test('缺失键回退默认值', () {
      final restored = parseReadAloudPreferences(const <String, String>{});
      expect(restored.enabled, ReadAloudPreferences.defaults.enabled);
      expect(restored.autoRead, ReadAloudPreferences.defaults.autoRead);
      expect(restored.rate, ReadAloudPreferences.defaults.rate);
      expect(restored.pitch, ReadAloudPreferences.defaults.pitch);
      expect(restored.volume, ReadAloudPreferences.defaults.volume);
    });

    test('宽容解析 true/false 文本', () {
      final restored = parseReadAloudPreferences(const <String, String>{
        ReadAloudSettingKeys.enabled: 'true',
        ReadAloudSettingKeys.autoRead: 'false',
      });
      expect(restored.enabled, isTrue);
      expect(restored.autoRead, isFalse);
    });

    test('非法数值回退默认值，越界数值被钳制', () {
      final restored = parseReadAloudPreferences(const <String, String>{
        ReadAloudSettingKeys.rate: '5',
        ReadAloudSettingKeys.pitch: '0.1',
        ReadAloudSettingKeys.volume: '不是数字',
      });
      expect(restored.rate, 1.0);
      expect(restored.pitch, 0.5);
      expect(restored.volume, ReadAloudPreferences.defaults.volume);
    });
  });
}
