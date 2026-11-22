import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_migration_service.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/setting_card_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Phase 5a compatibility migration: old tree / legacy rows become one card
/// each, without writing to the old storage or losing a row.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late SettingCardRepositoryImpl cards;
  late SettingCardMigrationService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_setting_card_mig_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    // Opening the database also runs the startup migration against the empty
    // fixtures; tests below force a second run after seeding.
    await DatabaseService.database;
    cards = SettingCardRepositoryImpl(getDb: () => DatabaseService.database);
    service = SettingCardMigrationService(
      getDb: () => DatabaseService.database,
      cards: cards,
      clock: () => '2026-06-01T00:00:00.000',
    );
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> insertWorldview({
    required String id,
    String name = '银月大陆',
    String description = '一片被月光笼罩的大陆',
    String detailJson = '',
  }) async {
    final db = await DatabaseService.database;
    final detail = detailJson.isNotEmpty
        ? detailJson
        : jsonEncode(<String, Object?>{
            'format_version': 2,
            'mode': 'simple',
            'modules': <String, Object?>{
              'overview': <String, Object?>{
                'summary': description,
                'status': 'confirmed',
              },
            },
          });
    await db.insert('worldview_presets', <String, Object?>{
      'id': id,
      'name': name,
      'description': description,
      'detail_json': detail,
      'entries_json': '[]',
      'mode': 'adventure',
      'created_at': '2026-01-01T00:00:00.000',
      'updated_at': '2026-01-02T00:00:00.000',
    });
  }

  Future<void> insertCharacter(String id) async {
    final db = await DatabaseService.database;
    await db.insert('character_cards', <String, Object?>{
      'id': id,
      'name': '林恩',
      'json_data': jsonEncode(<String, Object?>{
        'name': '林恩',
        'description': '他是一名游侠',
        'personality': '沉默寡言',
        'tags': <String>['游侠'],
      }),
      'source': 'local',
      'created_at': '2026-01-03T00:00:00.000',
      'updated_at': '2026-01-04T00:00:00.000',
    });
  }

  Future<void> insertNativeTree() async {
    final db = await DatabaseService.database;
    await db.insert('resources', <String, Object?>{
      'id': 'res_native_1',
      'type': 'worldview',
      'name': '原生世界',
      'summary': '只在树里存在',
      'status': 'confirmed',
      'metadata_json': '{}',
      'created_at': '2026-02-01T00:00:00.000',
      'updated_at': '2026-02-02T00:00:00.000',
    });
    await db.insert('resource_sections', <String, Object?>{
      'id': 'sec_native_1',
      'resource_id': 'res_native_1',
      'title': '地点',
      'summary': '',
      'sort_order': 0,
      'status': 'draft',
      'created_at': '2026-02-01T00:00:00.000',
      'updated_at': '2026-02-01T00:00:00.000',
    });
    await db.insert('resource_parts', <String, Object?>{
      'id': 'part_native_1',
      'section_id': 'sec_native_1',
      'title': '银月城',
      'content': '一座学术重镇。',
      'sort_order': 0,
      'status': 'draft',
      'content_hash': '',
      'created_at': '2026-02-01T00:00:00.000',
      'updated_at': '2026-02-01T00:00:00.000',
    });
  }

  test('legacy worldview becomes one markdown card under the resource id',
      () async {
    await insertWorldview(id: 'w1');

    final stats = await service.run(force: true);

    expect(stats.created, 1);
    final card = await cards.findById('res_legacy_worldview_presets_w1');
    expect(card, isNotNull);
    expect(card!.kind, SettingCardKind.worldview);
    expect(card.name, '银月大陆');
    expect(card.legacyId, 'w1');
    expect(card.mode, 'adventure');
    expect(card.origin, SettingCardOrigin.legacyRow);
    expect(card.content, contains('## 概览'));
    expect(card.content, contains('一片被月光笼罩的大陆'));
    expect(card.createdAt, '2026-01-01T00:00:00.000');
  });

  test('legacy character card keeps its prose in one document', () async {
    await insertCharacter('ch1');

    await service.run(force: true);

    final card = await cards.findById('res_legacy_character_cards_ch1');
    expect(card, isNotNull);
    expect(card!.kind, SettingCardKind.character);
    expect(card.name, '林恩');
    expect(card.content, contains('他是一名游侠'));
    expect(card.content, contains('沉默寡言'));
  });

  test('a tree-native resource is merged from its sections and parts',
      () async {
    await insertNativeTree();

    await service.run(force: true);

    final card = await cards.findById('res_native_1');
    expect(card, isNotNull);
    expect(card!.origin, SettingCardOrigin.legacyTree);
    expect(card.name, '原生世界');
    expect(card.status, SettingCardStatus.confirmed);
    expect(card.content, contains('## 地点'));
    expect(card.content, contains('### 银月城'));
    expect(card.content, contains('一座学术重镇。'));
  });

  test('re-running never duplicates or overwrites a user-edited card',
      () async {
    await insertWorldview(id: 'w1');
    await service.run(force: true);

    final original = await cards.findById('res_legacy_worldview_presets_w1');
    await cards.save(original!.copyWith(content: '用户改写后的正文'));

    final second = await service.run(force: true);

    expect(second.created, 0);
    final cards1 = await cards.list(kind: SettingCardKind.worldview);
    expect(cards1, hasLength(1));
    expect(cards1.single.content, '用户改写后的正文');
  });

  test('a damaged legacy row is preserved verbatim instead of dropped',
      () async {
    await insertWorldview(
      id: 'broken',
      name: '损坏的设定',
      detailJson: '{not-valid-json',
    );

    await service.run(force: true);

    final card = await cards.findById('res_legacy_worldview_presets_broken');
    expect(card, isNotNull);
    expect(card!.name, '损坏的设定');
    expect(card.content, contains('detail_json'));
    expect(card.content, contains('{not-valid-json'));
  });

  test('a completed run is recorded so later launches skip the merge',
      () async {
    await insertWorldview(id: 'w1');
    await service.run(force: true);
    await insertWorldview(id: 'w2', name: '第二世界');

    final skipped = await service.run();
    expect(skipped.created, 0);
    expect(await cards.findById('res_legacy_worldview_presets_w2'), isNull);

    final forced = await service.run(force: true);
    expect(forced.created, 1);
    expect(
      await cards.findById('res_legacy_worldview_presets_w2'),
      isNotNull,
    );
  });

  test('startup marks the migration complete on an empty library', () async {
    // setUp opened the database, which ran the startup migration.
    expect(await service.isComplete(), isTrue);
    expect(await cards.list(), isEmpty);
  });
}
