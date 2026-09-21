import '../../domain/read_aloud/read_aloud_contracts.dart';
import '../repositories/settings_repository.dart';
import 'language_tag.dart';

/// 朗读偏好在 settings KV 中的键。
///
/// 复用现有 `ISettingsRepository`（settings 表 KV），不新增数据库 schema。
class ReadAloudSettingKeys {
  const ReadAloudSettingKeys._();

  static const String enabled = 'tts_enabled';
  static const String autoRead = 'tts_auto_read';
  static const String rate = 'tts_rate';
  static const String pitch = 'tts_pitch';
  static const String volume = 'tts_volume';

  /// 语言模式：`auto` / `fixed`。
  static const String languageMode = 'tts_language_mode';

  /// 固定/兜底语言（归一化 BCP-47）。
  static const String languageTag = 'tts_language_tag';
}

/// 从已加载的 settings map 解析朗读偏好。
///
/// 这是唯一的偏好读取路径：`SettingsProvider` 启动时本来就一次性读取全部
/// settings，朗读系统复用它，避免再单独发起一次数据库读取（那会与既有启动
/// 流程争抢连接并改变时序）。缺键回退默认值，越界数值被钳制。
///
/// 老用户没有 `tts_language_mode` / `tts_language_tag` 键时无损回退默认
/// （`auto` + `zh-CN`），不会导致既有朗读设置加载失败。
ReadAloudPreferences parseReadAloudPreferences(Map<String, String> values) {
  const defaults = ReadAloudPreferences.defaults;
  return ReadAloudPreferences(
    enabled: _readBool(values[ReadAloudSettingKeys.enabled], defaults.enabled),
    autoRead:
        _readBool(values[ReadAloudSettingKeys.autoRead], defaults.autoRead),
    rate: _readDouble(values[ReadAloudSettingKeys.rate], defaults.rate)
        .clamp(0.0, 1.0),
    pitch: _readDouble(values[ReadAloudSettingKeys.pitch], defaults.pitch)
        .clamp(0.5, 2.0),
    volume: _readDouble(values[ReadAloudSettingKeys.volume], defaults.volume)
        .clamp(0.0, 1.0),
    languageMode: _readLanguageMode(
      values[ReadAloudSettingKeys.languageMode],
      defaults.languageMode,
    ),
    languageTag: _readLanguageTag(
      values[ReadAloudSettingKeys.languageTag],
      defaults.languageTag,
    ),
  );
}

/// 朗读偏好持久化端口（只写）。Authority 依赖这个抽象，测试可脱离 SQLite。
abstract class ReadAloudSettingsStore {
  Future<void> save(ReadAloudPreferences preferences);
}

/// 基于 [ISettingsRepository] 的实现，接入现有 SettingsRepository Authority。
class SettingsRepoReadAloudStore implements ReadAloudSettingsStore {
  SettingsRepoReadAloudStore(this._repository);

  final ISettingsRepository _repository;

  @override
  Future<void> save(ReadAloudPreferences preferences) async {
    await _repository.setSettings(<String, String>{
      ReadAloudSettingKeys.enabled: preferences.enabled ? '1' : '0',
      ReadAloudSettingKeys.autoRead: preferences.autoRead ? '1' : '0',
      ReadAloudSettingKeys.rate: preferences.rate.toString(),
      ReadAloudSettingKeys.pitch: preferences.pitch.toString(),
      ReadAloudSettingKeys.volume: preferences.volume.toString(),
      ReadAloudSettingKeys.languageMode: preferences.languageMode.name,
      ReadAloudSettingKeys.languageTag: preferences.languageTag,
    });
  }
}

bool _readBool(String? raw, bool fallback) {
  if (raw == null) return fallback;
  switch (raw.trim().toLowerCase()) {
    case '1':
    case 'true':
    case 'yes':
      return true;
    case '0':
    case 'false':
    case 'no':
      return false;
    default:
      return fallback;
  }
}

double _readDouble(String? raw, double fallback) {
  if (raw == null) return fallback;
  return double.tryParse(raw.trim()) ?? fallback;
}

ReadAloudLanguageMode _readLanguageMode(
  String? raw,
  ReadAloudLanguageMode fallback,
) {
  if (raw == null) return fallback;
  switch (raw.trim().toLowerCase()) {
    case 'auto':
      return ReadAloudLanguageMode.auto;
    case 'fixed':
      return ReadAloudLanguageMode.fixed;
    default:
      // 非法值安全修复为默认，而不是让既有设置加载失败。
      return fallback;
  }
}

String _readLanguageTag(String? raw, String fallback) {
  final normalized = normalizeBcp47(raw);
  return normalized.isEmpty ? fallback : normalized;
}
