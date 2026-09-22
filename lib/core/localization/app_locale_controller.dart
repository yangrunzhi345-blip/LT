import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';

import '../../services/read_aloud/read_aloud_controller.dart';
import '../../services/read_aloud/read_aloud_settings_store.dart';
import '../../services/repositories/settings_repository.dart';
import 'app_locale.dart';

/// 应用级语言唯一 Authority (Single Source of Truth)
///
/// 职责：
/// 1. 管理并发布 App UI 当前语言（[currentLocale]、[locale]）；
/// 2. 负责 `ui_locale` 的持久化与读取，不存在则标记首次启动；
/// 3. 在首次启动确认语言时，若 TTS 尚未被用户显式配置，初始化其对应的推荐 fallback 语言；
/// 4. 之后与 TTS Language 彻底隔离，修改 UI Locale 绝不覆盖用户的 TTS 偏好。
class AppLocaleController extends ChangeNotifier {
  AppLocaleController({
    required ISettingsRepository settingsRepo,
    ReadAloudController? readAloudController,
  })  : _settingsRepo = settingsRepo,
        _readAloudController = readAloudController;

  final ISettingsRepository _settingsRepo;
  final ReadAloudController? _readAloudController;

  AppLocale _currentLocale = AppLocale.fallback;
  bool _isFirstRun = false;
  bool _isLoaded = false;

  /// 当前生效的 [AppLocale]。
  AppLocale get currentLocale => _currentLocale;

  /// 供 [MaterialApp.locale] 使用的 [Locale]。
  Locale get locale => _currentLocale.locale;

  /// 是否为首次启动（即数据库中尚未持久化 `ui_locale`）。
  bool get isFirstRun => _isFirstRun;

  /// 设置是否已从存储完成加载。
  bool get isLoaded => _isLoaded;

  /// 从设置仓库加载 UI 语言偏好。
  ///
  /// 若无持久化值：
  /// - 标记为首次启动 [isFirstRun] = true；
  /// - 根据当前系统语言自动推荐并高亮初始语言（不支持则为 English）。
  /// 若已有持久化值：
  /// - [isFirstRun] = false；
  /// - 还原保存的语言；非法值安全回退到 English。
  Future<void> loadLocale() async {
    try {
      final stored = await _settingsRepo.getSetting(AppLocaleKeys.uiLocale);
      if (stored == null) {
        _isFirstRun = true;
        final systemLocale = PlatformDispatcher.instance.locale;
        _currentLocale = AppLocale.matchSystemLocale(systemLocale);
      } else {
        _isFirstRun = false;
        _currentLocale = AppLocale.fromCode(stored);
      }
    } catch (e) {
      debugPrint(
          'AppLocaleController.loadLocale failed, falling back to system locale: $e');
      _isFirstRun = false;
      final systemLocale = PlatformDispatcher.instance.locale;
      _currentLocale = AppLocale.matchSystemLocale(systemLocale);
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// 更改应用 UI 语言。
  ///
  /// [isFirstRunSetup]: 是否为首次启动引导流程中的确认操作。
  /// 仅在 [isFirstRunSetup] == true 且用户尚未显式配置 TTS 语言时，
  /// 才将 TTS 固定/兜底语言初始化为与 UI 对应的推荐语言。
  /// 日常在设置页中切换 UI 语言时，[isFirstRunSetup] 默认为 false，
  /// 绝不覆盖用户的既有 TTS 偏好。
  Future<void> setLocale(
    AppLocale newLocale, {
    bool isFirstRunSetup = false,
  }) async {
    _currentLocale = newLocale;
    _isFirstRun = false;
    await _settingsRepo.setSetting(AppLocaleKeys.uiLocale, newLocale.code);

    if (isFirstRunSetup) {
      final existingTtsTag =
          await _settingsRepo.getSetting(ReadAloudSettingKeys.languageTag);
      if (existingTtsTag == null || existingTtsTag.trim().isEmpty) {
        final fallbackTtsTag = newLocale.defaultTtsTag;
        await _settingsRepo.setSetting(
          ReadAloudSettingKeys.languageTag,
          fallbackTtsTag,
        );
        final readAloud = _readAloudController;
        if (readAloud != null) {
          await readAloud.setFixedLanguage(fallbackTtsTag);
        }
      }
    }

    notifyListeners();
  }
}
