import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_imports.dart';

void main() {
  group('D1 generation authority reachability', () {
    test('the production wizard does not invoke legacy generation authorities',
        () {
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

    test('character editor has no Adventure AI generation authority', () {
      final source = File(
        'lib/screens/resource_library/character_card_edit_page.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('adventureAiControllerProvider')));
      expect(source, isNot(contains('generateResourceCharacter')));
      expect(source, isNot(contains('generateDetailedResourceCharacter')));
    });

    test('production composition keeps no import generation runtime', () {
      final providers =
          File('lib/providers/riverpod_providers.dart').readAsStringSync();
      expect(providers, isNot(contains('ImportGenerationRuntime')));
      expect(providers, isNot(contains('ImportRecoveryService')));
    });

    test('legacy import authority is absent from production sources', () {
      final sources = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          sources.add(entity.readAsStringSync());
        }
      }
      for (final symbol in <String>[
        'ImportConversationCharacterUseCase',
        'ResourceCardImportUseCase',
        'ImportWorldviewUseCase',
        'SceneBatchImportUseCase',
        'ResourceLibraryImportController',
        'ResourceCardImportController',
        'SceneBatchImportController',
        'resourceLibraryImportControllerProvider',
        'resourceCardImportControllerProvider',
        'sceneBatchImportControllerProvider',
      ]) {
        expect(sources.any((source) => source.contains(symbol)), isFalse,
            reason: 'legacy symbol remains in lib: $symbol');
      }
    });

    test('removed creation authorities stay removed', () {
      final violations = <String>[];
      for (final path in dartFilesUnder('lib')) {
        final source = File(path).readAsStringSync();
        if (source.contains('LegacyCreationBridge') ||
            source.contains('legacy_creation_bridge.dart') ||
            source.contains('entryCreationPipeline') ||
            source.contains('ResourceCreationPipeline')) {
          violations.add('$path contains a removed creation authority');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });
}
