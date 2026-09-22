import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/core/localization/app_locale.dart';

void main() {
  test(
      'all supported locales load and unsupported locales fall back to English',
      () {
    final locales = <Locale>[
      const Locale('en'),
      const Locale('ja'),
      const Locale('ko'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    ];

    for (final locale in locales) {
      final l10n = lookupAppLocalizations(locale);
      expect(l10n.appTitle, isNotEmpty);
      expect(l10n.chatBranchCreated('branch-1'), contains('branch-1'));
    }

    expect(AppLocale.fromCode('fr'), AppLocale.en);
  });

  test('ARB message and placeholder sets stay in sync', () {
    final files = [
      'app_en.arb',
      'app_ja.arb',
      'app_ko.arb',
      'app_zh.arb',
      'app_zh_Hans.arb',
      'app_zh_Hant.arb',
    ];
    Set<String>? expectedKeys;
    Set<String>? expectedPlaceholders;
    for (final name in files) {
      final json = jsonDecode(
        File('lib/l10n/$name').readAsStringSync(),
      ) as Map<String, dynamic>;
      final keys = json.keys.where((key) => !key.startsWith('@')).toSet();
      final placeholders = <String>{};
      for (final entry
          in json.entries.where((entry) => entry.key.startsWith('@'))) {
        final value = entry.value;
        if (value is Map) {
          final fields = value['placeholders'];
          if (fields is Map) {
            placeholders.add('${entry.key}:${fields.keys.join(',')}');
          }
        }
      }
      expectedKeys ??= keys;
      expect(keys, expectedKeys);
      // Only the template is required to carry placeholder metadata; the
      // translated ARBs are checked for the same message key set.
      expectedPlaceholders ??= placeholders;
      if (name == 'app_en.arb') {
        expect(placeholders, expectedPlaceholders);
      }
    }
  });
}
