import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/localization/app_locale.dart';
import 'package:lt_dialogue/core/localization/app_locale_controller.dart';
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
  group('AppLocale Domain & Helpers', () {
    test('fromCode 解析支持的两种语言及变体', () {
      expect(AppLocale.fromCode('en'), AppLocale.en);
      expect(AppLocale.fromCode('en-US'), AppLocale.en);
      expect(AppLocale.fromCode('en_GB'), AppLocale.en);

      expect(AppLocale.fromCode('zh-Hans'), AppLocale.zhHans);
      expect(AppLocale.fromCode('zh_CN'), AppLocale.zhHans);
      expect(AppLocale.fromCode('zh'), AppLocale.zhHans);

      // Legacy Traditional Chinese codes converge on the single Chinese locale.
      expect(AppLocale.fromCode('zh-Hant'), AppLocale.zhHans);
      expect(AppLocale.fromCode('zh_TW'), AppLocale.zhHans);
      expect(AppLocale.fromCode('zh-HK'), AppLocale.zhHans);
    });

    test('fromCode 非法值与空值 fail-safe 回退到 English', () {
      expect(AppLocale.fromCode(null), AppLocale.en);
      expect(AppLocale.fromCode(''), AppLocale.en);
      expect(AppLocale.fromCode('invalid_locale'), AppLocale.en);
      expect(AppLocale.fromCode('fr-FR'), AppLocale.en);
      expect(AppLocale.fromCode('de'), AppLocale.en);
      expect(AppLocale.fromCode('ja'), AppLocale.en);
      expect(AppLocale.fromCode('ko'), AppLocale.en);
    });

    test('matchSystemLocale 正确识别支持语言并对不支持语言回退到 English', () {
      expect(
        AppLocale.matchSystemLocale(const Locale('zh', 'CN')),
        AppLocale.zhHans,
      );
      expect(
        AppLocale.matchSystemLocale(
          const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ),
        AppLocale.zhHans,
      );
      expect(
        AppLocale.matchSystemLocale(const Locale('zh', 'TW')),
        AppLocale.zhHans,
      );
      expect(
        AppLocale.matchSystemLocale(const Locale('en', 'US')),
        AppLocale.en,
      );
      expect(
        AppLocale.matchSystemLocale(const Locale('fr', 'FR')),
        AppLocale.en,
      );
      expect(
        AppLocale.matchSystemLocale(const Locale('ru')),
        AppLocale.en,
      );
      expect(AppLocale.matchSystemLocale(const Locale('ja')), AppLocale.en);
      expect(AppLocale.matchSystemLocale(const Locale('ko')), AppLocale.en);
    });
  });

  group('AppLocaleController Authority', () {
    test('无持久化值时标记为首次启动 isFirstRun = true', () async {
      final repo = _MemorySettingsRepository();
      final controller = AppLocaleController(settingsRepo: repo);

      await controller.loadLocale();

      expect(controller.isFirstRun, isTrue);
      expect(controller.isLoaded, isTrue);
      expect(repo.values[AppLocaleKeys.uiLocale], isNull);
    });

    test('保存所有支持语言并持久化', () async {
      final repo = _MemorySettingsRepository();
      final controller = AppLocaleController(settingsRepo: repo);

      for (final target in AppLocale.values) {
        await controller.setLocale(target);
        expect(controller.currentLocale, target);
        expect(controller.locale, target.locale);
        expect(repo.values[AppLocaleKeys.uiLocale], target.code);
        expect(controller.isFirstRun, isFalse);
      }
    });

    test('持久化非法值时启动 fail-safe 回退到 English', () async {
      final repo = _MemorySettingsRepository();
      repo.values[AppLocaleKeys.uiLocale] = 'unknown_corrupted_value';
      final controller = AppLocaleController(settingsRepo: repo);

      await controller.loadLocale();

      expect(controller.isFirstRun, isFalse);
      expect(controller.currentLocale, AppLocale.en);
      expect(controller.locale, const Locale('en'));
    });

    test('重启后从存储恢复语言', () async {
      final repo = _MemorySettingsRepository();
      repo.values[AppLocaleKeys.uiLocale] = 'zh-Hans';

      final controller = AppLocaleController(settingsRepo: repo);
      await controller.loadLocale();

      expect(controller.isFirstRun, isFalse);
      expect(controller.currentLocale, AppLocale.zhHans);
      expect(controller.locale, AppLocale.zhHans.locale);
    });

    test('连续热切换语言且状态正确通知', () async {
      final repo = _MemorySettingsRepository();
      final controller = AppLocaleController(settingsRepo: repo);
      await controller.loadLocale();

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await controller.setLocale(AppLocale.zhHans);
      expect(controller.currentLocale, AppLocale.zhHans);
      expect(notifyCount, 1);

      await controller.setLocale(AppLocale.en);
      expect(controller.currentLocale, AppLocale.en);
      expect(notifyCount, 2);
    });
  });

  group('AppLocale 与 TTS 隔离策略', () {
    test('首次启动 setup 时，若 TTS 未配置，初始化推荐 fallback', () async {
      final repo = _MemorySettingsRepository();
      final controller = AppLocaleController(settingsRepo: repo);
      await controller.loadLocale();

      await controller.setLocale(AppLocale.zhHans, isFirstRunSetup: true);

      expect(repo.values[AppLocaleKeys.uiLocale], 'zh-Hans');
      expect(repo.values[ReadAloudSettingKeys.languageTag], 'zh-CN');
    });

    test('首次启动 setup 时，各语言对应的 TTS fallback 映射准确', () async {
      final expectedFallbacks = {
        AppLocale.en: 'en-US',
        AppLocale.zhHans: 'zh-CN',
      };

      for (final entry in expectedFallbacks.entries) {
        final repo = _MemorySettingsRepository();
        final controller = AppLocaleController(settingsRepo: repo);
        await controller.setLocale(entry.key, isFirstRunSetup: true);

        expect(
          repo.values[ReadAloudSettingKeys.languageTag],
          entry.value,
          reason: 'UI ${entry.key.code} should fallback to TTS ${entry.value}',
        );
      }
    });

    test('若 TTS 已有配置，首次启动 setup 也绝不覆盖既有 TTS 语言', () async {
      final repo = _MemorySettingsRepository();
      repo.values[ReadAloudSettingKeys.languageTag] = 'ko-KR';

      final controller = AppLocaleController(settingsRepo: repo);
      await controller.setLocale(AppLocale.zhHans, isFirstRunSetup: true);

      expect(repo.values[AppLocaleKeys.uiLocale], 'zh-Hans');
      expect(repo.values[ReadAloudSettingKeys.languageTag], 'ko-KR');
    });

    test('日常切换 UI 语言 (isFirstRunSetup=false) 绝对不改变 TTS 语言', () async {
      final repo = _MemorySettingsRepository();
      repo.values[ReadAloudSettingKeys.languageTag] = 'ja-JP';

      final controller = AppLocaleController(settingsRepo: repo);

      await controller.setLocale(AppLocale.en);
      expect(repo.values[AppLocaleKeys.uiLocale], 'en');
      expect(repo.values[ReadAloudSettingKeys.languageTag], 'ja-JP');

      await controller.setLocale(AppLocale.zhHans);
      expect(repo.values[AppLocaleKeys.uiLocale], 'zh-Hans');
      expect(repo.values[ReadAloudSettingKeys.languageTag], 'ja-JP');
    });
  });
}
