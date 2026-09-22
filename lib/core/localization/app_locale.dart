import 'package:flutter/material.dart';

/// 支持的应用 UI 语言枚举。
///
/// 严格限定于首发 5 种语言：
/// 1. English (en)
/// 2. 简体中文 (zh-Hans)
/// 3. 繁體中文 (zh-Hant)
/// 4. 日本語 (ja)
/// 5. 한국어 (ko)
enum AppLocale {
  en(
    code: 'en',
    nativeName: 'English',
    locale: Locale('en'),
    defaultTtsTag: 'en-US',
  ),
  zhHans(
    code: 'zh-Hans',
    nativeName: '简体中文',
    locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    defaultTtsTag: 'zh-CN',
  ),
  zhHant(
    code: 'zh-Hant',
    nativeName: '繁體中文',
    locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    defaultTtsTag: 'zh-TW',
  ),
  ja(
    code: 'ja',
    nativeName: '日本語',
    locale: Locale('ja'),
    defaultTtsTag: 'ja-JP',
  ),
  ko(
    code: 'ko',
    nativeName: '한국어',
    locale: Locale('ko'),
    defaultTtsTag: 'ko-KR',
  );

  const AppLocale({
    required this.code,
    required this.nativeName,
    required this.locale,
    required this.defaultTtsTag,
  });

  /// 存储在设置表及协议中的规范化 code。
  final String code;

  /// 语言自身名称（用于首次启动与切换界面）。
  final String nativeName;

  /// Flutter 对应的 [Locale]。
  final Locale locale;

  /// 首次启动选择该 UI 语言且用户从未配置 TTS 时，推荐的 TTS 语言 tag。
  final String defaultTtsTag;

  /// 兜底语言（English）。
  static const AppLocale fallback = AppLocale.en;

  /// 解析存储字符串为 [AppLocale]。
  ///
  /// 支持标准 BCP-47、下划线及常见变体；遇到未知或非法值时，安全回退到 [AppLocale.en]。
  static AppLocale fromCode(String? raw) {
    if (raw == null) return fallback;
    final normalized = raw.trim().replaceAll('_', '-').toLowerCase();
    if (normalized.isEmpty) return fallback;

    switch (normalized) {
      case 'en':
      case 'en-us':
      case 'en-gb':
        return AppLocale.en;
      case 'zh-hans':
      case 'zh-cn':
      case 'zh-sg':
      case 'zh':
        return AppLocale.zhHans;
      case 'zh-hant':
      case 'zh-tw':
      case 'zh-hk':
      case 'zh-mo':
        return AppLocale.zhHant;
      case 'ja':
      case 'ja-jp':
        return AppLocale.ja;
      case 'ko':
      case 'ko-kr':
        return AppLocale.ko;
      default:
        return fallback;
    }
  }

  /// 根据系统 Locale 匹配最佳推荐语言。
  ///
  /// 如果系统语言在支持列表中，则返回对应语言；若不支持，返回 [AppLocale.en]。
  static AppLocale matchSystemLocale(Locale? systemLocale) {
    if (systemLocale == null) return fallback;
    final lang = systemLocale.languageCode.toLowerCase();
    final script = systemLocale.scriptCode?.toLowerCase();
    final country = systemLocale.countryCode?.toUpperCase();

    if (lang == 'zh') {
      if (script == 'hant' ||
          country == 'TW' ||
          country == 'HK' ||
          country == 'MO') {
        return AppLocale.zhHant;
      }
      return AppLocale.zhHans;
    }

    if (lang == 'ja') return AppLocale.ja;
    if (lang == 'ko') return AppLocale.ko;
    if (lang == 'en') return AppLocale.en;

    return fallback;
  }
}

/// 语言设置相关的持久化键。
class AppLocaleKeys {
  const AppLocaleKeys._();

  /// 应用 UI 语言设置键。若该键在 settings 仓库中不存在，则视为首次启动。
  static const String uiLocale = 'ui_locale';
}
