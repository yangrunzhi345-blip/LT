import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/localization/app_event_localizer.dart';
import 'package:lt_dialogue/domain/events/app_event.dart';
import 'package:lt_dialogue/domain/events/app_event_codec.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

void main() {
  test('event codec round trips a locale-neutral payload', () {
    const event = AppEvent(
      code: AppEventCode.combatVictory,
      payload: {'exp': 100, 'gold': 20},
    );
    final decoded = AppEventCodec.decode(AppEventCodec.encode(event));
    expect(decoded?.code, AppEventCode.combatVictory);
    expect(decoded?.payload['exp'], 100);
    expect(AppEventCodec.decode('legacy text'), isNull);
  });

  test('same event renders in the active locale', () {
    const event = AppEvent(
      code: AppEventCode.combatVictory,
      payload: {'exp': 100, 'gold': 20},
    );
    final zh = localizeAppEvent(
      lookupAppLocalizations(const Locale('zh')),
      event,
    );
    final en = localizeAppEvent(
      lookupAppLocalizations(const Locale('en')),
      event,
    );
    final ja = localizeAppEvent(
      lookupAppLocalizations(const Locale('ja')),
      event,
    );
    expect(zh, contains('100'));
    expect(en, contains('100'));
    expect(ja, contains('100'));
    expect(zh, isNot(en));
    expect(ja, isNot(en));
  });
}
