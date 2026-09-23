import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/core/localization/app_locale.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';

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
      expect(l10n.unnamedSceneTitle, isNotEmpty);
      const unnamedResource = ResourceLibraryItem(
        id: 'empty-name',
        type: ResourceType.worldview,
        name: '',
        summary: '',
        updatedAt: '',
        status: ResourceDisplayStatus.ready,
        isStudioAvailable: false,
      );
      expect(unnamedResource.localizedName(l10n), l10n.resourceUnnamed);
      final statusPresetTexts = <String>[
        l10n.statusPresetSanityLabel,
        l10n.statusPresetSanityName,
        l10n.statusPresetSanityDescription,
        l10n.statusPresetAffinityLabel,
        l10n.statusPresetAffinityName,
        l10n.statusPresetAffinityDescription,
        l10n.statusPresetCorruptionLabel,
        l10n.statusPresetCorruptionName,
        l10n.statusPresetCorruptionDescription,
        l10n.statusPresetHungerLabel,
        l10n.statusPresetHungerName,
        l10n.statusPresetHungerDescription,
        l10n.statusPresetMagicLabel,
        l10n.statusPresetMagicName,
        l10n.statusPresetMagicDescription,
        l10n.statusPresetPressureLabel,
        l10n.statusPresetPressureName,
        l10n.statusPresetPressureDescription,
        l10n.statusPresetArmorLabel,
        l10n.statusPresetArmorName,
        l10n.statusPresetArmorDescription,
        l10n.statusPresetSpiritLabel,
        l10n.statusPresetSpiritName,
        l10n.statusPresetSpiritDescription,
      ];
      expect(statusPresetTexts.every((text) => text.isNotEmpty), isTrue);
      expect(l10n.chatBranchCreated('branch-1'), contains('branch-1'));
      expect(l10n.sectionValidationPassed('Intro'), contains('Intro'));
      expect(l10n.sectionValidationFailed('Intro', 2), contains('2'));
      expect(l10n.sectionRegenerated('Intro', 2, 3), contains('2'));
      expect(l10n.capacityCompressionPublished(120), contains('120'));
      expect(l10n.capacityRetryBudgetExhausted(2), contains('2'));
      expect(l10n.revisionRestored(l10n.revisionCauseGeneration),
          contains(l10n.revisionCauseGeneration));
      expect(l10n.revisionItemSubtitle('2026-09-23', 12, 4321), contains('12'));
      expect(
          l10n.revisionItemSubtitle('2026-09-23', 12, 4321), contains('4321'));
      expect(
        l10n.capacityCompressionRunSummary(1, 0, 2, 1, 0),
        contains('1'),
      );
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
      expectedPlaceholders ??= placeholders;
      expect(placeholders, expectedPlaceholders);
    }
  });
}
