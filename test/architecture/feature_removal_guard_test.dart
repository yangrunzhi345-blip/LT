import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/services/database_service.dart';
import 'source_imports.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Feature Removal Architecture Guard - Files and Symbols', () {
    test('deleted files must not exist in repository', () {
      const deletedFiles = [
        'lib/managers/quest_manager.dart',
        'lib/models/quest.dart',
        'lib/screens/chat/widgets/quest_screen.dart',
        'lib/screens/chat/widgets/world_map.dart',
        'lib/core/theme/map_terrain_visuals.dart',
        'lib/application/adventure/map_generation_use_case.dart',
        'lib/services/narrative_map_service.dart',
        'lib/models/narrative_map.dart',
        'lib/models/map_encounter.dart',
        'test/unit/quest_manager_test.dart',
      ];

      for (final relativePath in deletedFiles) {
        final file = File(relativePath);
        expect(
          file.existsSync(),
          isFalse,
          reason:
              'File $relativePath was permanently removed and must not exist',
        );
      }
    });

    test('lib/ sources must not reference deleted quest and map symbols', () {
      const bannedSymbols = [
        'QuestManager',
        'QuestScreen',
        'WorldMapScreen',
        'NarrativeMapService',
        'NarrativeMapGraph',
        'MapEncounter',
        'MapGenerationUseCase',
        'MapTerrainVisuals',
        'getQuests',
        'saveQuest',
        'deleteQuest',
        'getNarrativeMap',
        'bootstrapNarrativeMap',
        'mergeNarrativeMapSeeds',
        'ensureNarrativeMapState',
        'applyMapMovement',
        'generateNarrativeMap',
      ];

      final violations = <String>[];
      final files = dartFilesUnder('lib');

      for (final filePath in files) {
        final content = File(filePath).readAsStringSync();
        for (final symbol in bannedSymbols) {
          final pattern = RegExp('\\b$symbol\\b');
          if (pattern.hasMatch(content)) {
            violations.add('$filePath references banned symbol "$symbol"');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'The following references to removed symbols were found:\n'
            '${violations.join('\n')}',
      );
    });
  });

  group('Feature Removal Architecture Guard - Database Schema v29', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lt_db_guard_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    const legacyTables = [
      'quests',
      'map_nodes',
      'map_connections',
      'map_node_aliases',
      'adventure_map_node_states',
      'adventure_map_connection_states',
      'adventure_map_state',
      'travel_events',
      'map_state_events',
      'map_extraction_candidates',
      'map_layouts',
      'movement_operations',
    ];

    test('fresh v29 schema installation creates zero quest and map tables',
        () async {
      final dbPath = '${tempDir.path}/fresh_v29.db';
      final db = await openDatabase(
        dbPath,
        version: 29,
        onCreate: (db, version) async {
          await DatabaseService.createV29Schema(db);
          await DatabaseService.createCreationLibrarySchema(db);
        },
      );

      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      final existingTableNames =
          tablesResult.map((row) => row['name'] as String).toSet();

      for (final table in legacyTables) {
        expect(
          existingTableNames.contains(table),
          isFalse,
          reason:
              'Fresh v29 database must NOT contain table "$table", but it was found',
        );
      }

      // Verify essential runtime tables exist
      const requiredTables = [
        'adventures',
        'messages',
        'game_state',
        'summaries',
        'world_entries',
        'branches',
        'bookmarks',
        'settings',
        'skills',
        'character_skills',
        'equipment',
        'inventory_items',
        'api_keys',
        'adventure_runtime_heads',
        'adventure_runtime_entities',
        'adventure_state_commits',
        'adventure_state_changes',
        'scene_dialogue_turns',
        'scene_presence',
        'scene_setting_candidates',
        'scene_runtime_state',
      ];

      for (final table in requiredTables) {
        expect(
          existingTableNames.contains(table),
          isTrue,
          reason: 'Fresh v29 database must contain core table "$table"',
        );
      }

      await db.close();
    });

    test(
        'migration from v28 to v29 safely drops all legacy quest and map tables',
        () async {
      final dbPath = '${tempDir.path}/migrate_v28_to_v29.db';

      // Step 1: Open database at v28 and create v28 schema
      var db = await openDatabase(
        dbPath,
        version: 28,
        onCreate: (db, version) async {
          await DatabaseService.createV28Schema(db);
        },
      );

      // Verify that legacy tables exist in v28
      var tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      var tableNames = tablesResult.map((row) => row['name'] as String).toSet();
      expect(tableNames.contains('quests'), isTrue,
          reason: 'quests should exist before migration in v28');
      expect(tableNames.contains('map_nodes'), isTrue,
          reason: 'map_nodes should exist before migration in v28');
      await db.close();

      // Step 2: Open and migrate to v29
      db = await openDatabase(
        dbPath,
        version: 29,
        onUpgrade: (db, oldVersion, newVersion) async {
          await DatabaseService.migrateStepByStep(db, oldVersion, newVersion);
        },
      );

      // Verify that none of the legacy tables exist after v28 -> v29 migration
      tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      tableNames = tablesResult.map((row) => row['name'] as String).toSet();

      for (final table in legacyTables) {
        expect(
          tableNames.contains(table),
          isFalse,
          reason:
              'Table "$table" must be dropped by v28 -> v29 migration, but still exists',
        );
      }

      // Verify that core tables remain intact after migration
      expect(tableNames.contains('adventures'), isTrue);
      expect(tableNames.contains('messages'), isTrue);
      expect(tableNames.contains('game_state'), isTrue);
      expect(tableNames.contains('equipment'), isTrue);
      expect(tableNames.contains('inventory_items'), isTrue);

      await db.close();
    });
  });
}
