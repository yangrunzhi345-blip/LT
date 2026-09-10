import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/adventure/adventure_setup_use_case.dart';
import 'package:lt_dialogue/controllers/adventure_setup_controller.dart';
import 'package:lt_dialogue/models/character_card_entry.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';

/// Use case whose worldview source always fails, used to prove that a failing
/// asset type no longer blocks the other two.
class _BreakingWorldviewUseCase extends AdventureSetupUseCase {
  _BreakingWorldviewUseCase(super.repository);

  @override
  Future<List<Map<String, dynamic>>> loadWorldviewPresets() async {
    throw StateError('worldview source unavailable');
  }
}

Map<String, dynamic> _validCardRow({
  required String id,
  required String name,
  String? worldviewId,
}) =>
    {
      'id': id,
      'name': name,
      'matching_worldview_id': worldviewId,
      'json_data': jsonEncode({
        'data': {
          'name': name,
          'gender': '女',
          'age': '22',
          'profession': '学者',
          'description': '来自图书馆的旅人',
          'tags': ['学者', '旅人'],
        },
      }),
    };

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late LibraryRepositoryImpl repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_p0_loading_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    repo = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Poisoned character rows', () {
    test('undecodable rows stay isolated and never throw', () {
      final entry = CharacterCardEntry.fromRow({
        'id': 'row_broken',
        'name': '损坏卡',
        'json_data': '{"data": {"name": "未闭合',
      });

      expect(entry.id, 'row_broken');
      expect(entry.name, '损坏卡');
      expect(entry.hasParseError, isTrue);
      expect(entry.card.name, isEmpty);
      expect(entry.gender, isEmpty);
      expect(entry.background, isEmpty);
    });

    test('legacy rows with wrong field types are tolerated, not fatal', () {
      final entry = CharacterCardEntry.fromRow({
        'id': 'row_legacy',
        'name': '旧数据卡',
        'json_data': jsonEncode({
          'data': 42,
          'name': 7,
          'tags': '不是列表',
          'world_profile': '不是对象',
          'alternate_greetings': [1, 2],
        }),
      });

      expect(entry.hasParseError, isFalse);
      expect(entry.card.name, '7');
      expect(entry.card.tags, isEmpty);
      expect(entry.gender, isEmpty);
    });

    test('two valid rows survive next to one poisoned row', () async {
      await repo.saveWorldviewPreset(
        id: 'wv1',
        name: '星穹界',
        description: '机械与灵力交织',
        entriesJson: '[]',
        now: DateTime.now().toIso8601String(),
      );
      await repo.saveWorldviewPreset(
        id: 'wv2',
        name: '荒海界',
        description: '沉船与潮汐',
        entriesJson: '[]',
        now: DateTime.now().toIso8601String(),
      );
      await repo.saveCharacterCard(
        id: 'char_ok1',
        name: '亚瑟',
        jsonData:
            _validCardRow(id: 'char_ok1', name: '亚瑟')['json_data'] as String,
        source: '测试',
        now: DateTime.now().toIso8601String(),
        matchingWorldviewId: 'wv1',
      );
      await repo.saveCharacterCard(
        id: 'char_ok2',
        name: '薇薇安',
        jsonData:
            _validCardRow(id: 'char_ok2', name: '薇薇安')['json_data'] as String,
        source: '测试',
        now: DateTime.now().toIso8601String(),
      );
      // Persisted legacy row whose JSON cannot be decoded at all.
      await repo.saveCharacterCard(
        id: 'char_bad',
        name: '损坏卡',
        jsonData: '{"data": {"name": "未闭合',
        source: 'PNG导入',
        now: DateTime.now().toIso8601String(),
      );
      await repo.saveNpcCard(
        id: 'npc1',
        name: '酒馆老板',
        jsonData: jsonEncode({'name': '酒馆老板'}),
        source: '测试',
        now: DateTime.now().toIso8601String(),
      );
      await repo.saveNpcCard(
        id: 'npc2',
        name: '巡逻卫兵',
        jsonData: jsonEncode({'name': '巡逻卫兵'}),
        source: '测试',
        now: DateTime.now().toIso8601String(),
      );

      final controller = AdventureSetupController(
        useCase: AdventureSetupUseCase(repo),
      );
      await controller.loadInitialData();

      // Every asset type loads: one poisoned row cannot stop the rest.
      expect(controller.worldviewPresets, hasLength(2));
      expect(controller.characterCards, hasLength(3));
      expect(controller.npcCards, hasLength(2));
      expect(controller.worldviewError, isNull);
      expect(controller.characterError, isNull);
      expect(controller.npcError, isNull);

      final entries = controller.characterCardEntries;
      expect(entries, hasLength(3));

      final usable = entries.where((e) => !e.hasParseError).toList();
      expect(usable.map((e) => e.name), containsAll(['亚瑟', '薇薇安']));
      expect(controller.malformedCharacterCardCount, 1);

      final damaged = entries.singleWhere((e) => e.hasParseError);
      expect(damaged.id, 'char_bad');
      expect(damaged.name, '损坏卡');
      expect(damaged.card.name, isEmpty);
    });
  });

  group('Per-type load isolation', () {
    test('a worldview failure keeps characters and NPCs usable', () async {
      await repo.saveCharacterCard(
        id: 'char_ok1',
        name: '亚瑟',
        jsonData: jsonEncode({
          'data': {'name': '亚瑟'}
        }),
        source: '测试',
        now: DateTime.now().toIso8601String(),
      );
      await repo.saveNpcCard(
        id: 'npc1',
        name: '酒馆老板',
        jsonData: jsonEncode({'name': '酒馆老板'}),
        source: '测试',
        now: DateTime.now().toIso8601String(),
      );

      final controller = AdventureSetupController(
        useCase: _BreakingWorldviewUseCase(repo),
      );
      await controller.loadInitialData();

      expect(controller.worldviewPresets, isEmpty);
      expect(controller.worldviewError, isNotNull);
      expect(controller.characterCards, hasLength(1));
      expect(controller.characterError, isNull);
      expect(controller.npcCards, hasLength(1));
      expect(controller.npcError, isNull);
      expect(controller.hasPartialFailure, isTrue);
      expect(controller.error, contains('世界观'));
    });
  });
}
