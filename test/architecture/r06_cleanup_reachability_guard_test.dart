import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_imports.dart';

void main() {
  group('R06 cleanup reachability guard', () {
    test('deleted production and duplicate surfaces stay removed', () {
      const deletedFiles = <String>[
        'lib/application/resources/resource_context_compressor.dart',
        'lib/controllers/scene_approval_controller.dart',
        'lib/managers/multi_char_manager.dart',
        'lib/screens/chat/widgets/status_toast.dart',
        'test/support/viewport_test_helper.dart',
      ];
      for (final path in deletedFiles) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }

      const deletedSymbols = <String>[
        'SceneApprovalController',
        'sceneApprovalControllerProvider',
        'ResourceContextCompressor',
        'StatusToast',
        'completeFim',
        'generateStructuredJson',
        'generateDetailedWorldviewCoordinatorForTesting',
        'includeSetupContext',
      ];
      final violations = <String>[];
      for (final path in dartFilesUnder('lib')) {
        final source = File(path).readAsStringSync();
        for (final symbol in deletedSymbols) {
          if (source.contains(symbol)) {
            violations.add('$path contains $symbol');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('protected compatibility and production recovery surfaces remain', () {
      final database =
          File('lib/services/database_service.dart').readAsStringSync();
      final translation =
          File('lib/models/translation_mode.dart').readAsStringSync();
      final worldEntry = File('lib/models/world_entry.dart').readAsStringSync();
      final providers =
          File('lib/providers/riverpod_providers.dart').readAsStringSync();
      final narrative = File('lib/application/narrative/narrative_context.dart')
          .readAsStringSync();

      expect(database, contains('migrateStepByStep'));
      expect(database, contains('dropLegacyQuestAndMapTables'));
      expect(translation, contains('TranslationMode decode'));
      expect(translation, contains('storageCode'));
      expect(worldEntry, contains('WorldEntryPosition decode'));
      expect(worldEntry, contains("'before_prompt'"));
      expect(providers, contains('streamingGenerationRecoveryProvider'));
      expect(providers, contains('findInterruptedSessions'));
      expect(providers, contains('recoverInterruptedGeneration'));
      expect(providers, contains('resourceRevisionRepositoryProvider'));
      expect(narrative, contains('class ContextOrchestrator'));
      expect(narrative, contains('TokenEstimator'));
    });
  });
}
