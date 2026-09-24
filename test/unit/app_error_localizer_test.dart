import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/localization/app_error_localizer.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

void main() {
  test('every error code has localized copy in all supported locales', () {
    final localizations = <AppLocalizations>[
      lookupAppLocalizations(const Locale('en')),
      lookupAppLocalizations(const Locale('ja')),
      lookupAppLocalizations(const Locale('ko')),
      lookupAppLocalizations(const Locale('zh')),
      lookupAppLocalizations(const Locale('zh', 'Hans')),
      lookupAppLocalizations(const Locale('zh', 'Hant')),
    ];

    for (final l10n in localizations) {
      for (final code in AppErrorCode.values) {
        final error = AppDomainError(
          code: code,
          parameters: const {
            'current': 12,
            'limit': 10,
            'name': 'Demo resource',
            'details': 'invalid input',
          },
        );
        expect(localizeAppError(l10n, error).trim(), isNotEmpty,
            reason: '${l10n.localeName}: ${code.name}');
      }
    }
  });

  test('unknown failures never expose technical diagnostics', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final copy = localizeAppError(
      l10n,
      AppDomainError(
        code: AppErrorCode.unknown,
        debugMessage: 'DatabaseException: secret internal detail',
      ),
    );
    expect(copy, isNot(contains('DatabaseException')));
    expect(copy, isNot(contains('secret internal detail')));
  });
}
