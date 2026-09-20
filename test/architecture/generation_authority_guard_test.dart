import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('D1 generation authority reachability', () {
    test('production imports do not invoke legacy generation authorities', () {
      const paths = <String>[
        'lib/screens/resource_library/worldview_ai_import_page.dart',
        'lib/screens/resource_library/resource_card_ai_import_page.dart',
        'lib/screens/resource_library/scene_batch_import_page.dart',
        'lib/controllers/resource_library_import_controller.dart',
        'lib/controllers/resource_card_import_controller.dart',
        'lib/controllers/scene_batch_import_controller.dart',
      ];
      const forbidden = <String>[
        '.generateWorldview(',
        '.generateConversationCharacter(',
        '.importSelected(',
        '.identify(',
        'identifyCharacterNames(',
        'generateResourceCharacter(',
        'generateDetailedResourceCharacter(',
      ];

      final violations = <String>[];
      for (final path in paths) {
        final source = File(path).readAsStringSync();
        for (final symbol in forbidden) {
          if (source.contains(symbol)) violations.add('$path contains $symbol');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));

      final wizard = File(
        'lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart',
      ).readAsStringSync();
      expect(wizard, isNot(contains('.planWorldview(')));
      expect(wizard, isNot(contains('resourceCardImportControllerProvider')));
      for (final symbol in <String>[
        'generateWorldview(',
        'generateDetailedWorldview(',
        'generateConversationCharacter(',
        'generateResourceCharacter(',
        'generateDetailedResourceCharacter(',
      ]) {
        expect(wizard, isNot(contains(symbol)),
            reason: 'wizard contains $symbol');
      }
    });

    test('import controllers cannot turn planning into local completion', () {
      const paths = <String>[
        'lib/controllers/resource_library_import_controller.dart',
        'lib/controllers/resource_card_import_controller.dart',
        'lib/controllers/scene_batch_import_controller.dart',
      ];
      final violations = <String>[];
      for (final path in paths) {
        final source = File(path).readAsStringSync();
        if (RegExp(
          r'await\s+[^;]*\.plan(?:Worldview)?\([^;]*;[\s\S]{0,180}?phase\s*=\s*[^;]*completed',
        ).hasMatch(source)) {
          violations.add('$path maps planning directly to completed');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('character editor has no Adventure AI generation authority', () {
      final source = File(
        'lib/screens/resource_library/character_card_edit_page.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('adventureAiControllerProvider')));
      expect(source, isNot(contains('generateResourceCharacter')));
      expect(source, isNot(contains('generateDetailedResourceCharacter')));
    });

    test('production composition keeps one creation and generation runtime',
        () {
      final providers =
          File('lib/providers/riverpod_providers.dart').readAsStringSync();
      expect(providers, contains('resourceCreationPipelineProvider'));
      expect(providers, contains('resourceStudioRuntimeProvider'));
      expect(providers, contains('streamingGenerationRecoveryProvider'));
      expect(providers, isNot(contains('ImportGenerationRuntime')));
      expect(providers, isNot(contains('ImportRecoveryService')));
    });
  });
}
