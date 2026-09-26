import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/features/adventure/presentation/state/runtime_state_presentation.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';

void main() {
  final l10n = AppLocalizationsZh();

  test('uses known character name and generic fallback for unknown entities',
      () {
    expect(
      RuntimeStatePresentation.entityLabel(
        RuntimeEntityType.character,
        '林默',
        l10n,
      ),
      '林默',
    );
    expect(
      RuntimeStatePresentation.entityLabel(
        RuntimeEntityType.location,
        '   ',
        l10n,
      ),
      l10n.worldviewModuleState,
    );
  });

  test('maps paths and hides identifier values', () {
    expect(RuntimeStatePresentation.fieldLabel('hp', l10n),
        l10n.runtimeStateFieldHp);
    expect(
      RuntimeStatePresentation.valueLabel(
          'faction_id', 'faction-internal-42', l10n),
      l10n.runtimeStateConfigured,
    );
    expect(
      RuntimeStatePresentation.valueLabel('life_status', 'alive', l10n),
      l10n.runtimeStateAlive,
    );
    expect(
      RuntimeStatePresentation.fieldLabelWithMetadata(
        'custom_attributes.detected_stamina',
        l10n,
        customAttributeLabels: const {'detected_stamina': '体力'},
      ),
      '体力',
    );
    expect(
      RuntimeStatePresentation.fieldLabelWithMetadata(
        'custom_attributes.detected_missing',
        l10n,
      ),
      l10n.runtimeStateChangedState,
    );
  });

  test('suppresses protocol-like reasons without rewriting narrative text', () {
    expect(RuntimeStatePresentation.isSafeReason('消耗少量体力'), isTrue);
    expect(RuntimeStatePresentation.isSafeReason('entityId=char-42 revision=9'),
        isFalse);
    expect(
      RuntimeStatePresentation.resolveCause('scene_dialogue', l10n),
      l10n.runtimeStateCauseDialogue,
    );
  });
}
