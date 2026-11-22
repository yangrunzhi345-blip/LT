import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/services/repositories/setting_card_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Database db;
  late SettingCardRepositoryImpl repository;

  SettingCard card(
    String id, {
    SettingCardKind kind = SettingCardKind.character,
    String name = '卡片',
    String content = '正文',
    String? legacyId,
    String updatedAt = '2026-01-01T00:00:00.000',
  }) =>
      SettingCard(
        id: id,
        kind: kind,
        name: name,
        summary: '摘要',
        content: content,
        mode: 'adventure',
        metadata: const <String, Object?>{'source': 'test'},
        legacyId: legacyId,
        createdAt: '2026-01-01T00:00:00.000',
        updatedAt: updatedAt,
      );

  setUp(() async {
    db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => SettingCardRepositoryImpl.createSchema(db),
      ),
    );
    repository = SettingCardRepositoryImpl(getDb: () async => db);
  });

  tearDown(() async {
    await db.close();
  });

  test('save then findById round-trips every field', () async {
    await repository.save(card('c1', legacyId: 'legacy-1'));

    final loaded = await repository.findById('c1');

    expect(loaded, isNotNull);
    expect(loaded!.id, 'c1');
    expect(loaded.kind, SettingCardKind.character);
    expect(loaded.name, '卡片');
    expect(loaded.summary, '摘要');
    expect(loaded.content, '正文');
    expect(loaded.mode, 'adventure');
    expect(loaded.metadata['source'], 'test');
    expect(loaded.legacyId, 'legacy-1');
    expect(loaded.createdAt, '2026-01-01T00:00:00.000');
  });

  test('insertIfAbsent never overwrites an existing card', () async {
    expect(
        await repository.insertIfAbsent(card('c1', content: 'first')), isTrue);
    expect(
      await repository.insertIfAbsent(card('c1', content: 'second')),
      isFalse,
    );

    final loaded = await repository.findById('c1');
    expect(loaded!.content, 'first');
  });

  test('save updates an existing row instead of duplicating it', () async {
    await repository.save(card('c1', content: 'old'));
    await repository.save(card('c1', content: 'new'));

    final all = await repository.list();
    expect(all, hasLength(1));
    expect(all.single.content, 'new');
  });

  test('list filters by kind and orders newest-updated first', () async {
    await repository.save(card('a',
        kind: SettingCardKind.worldview, updatedAt: '2026-01-01T00:00:00.000'));
    await repository.save(card('b', updatedAt: '2026-03-01T00:00:00.000'));
    await repository.save(card('c', updatedAt: '2026-02-01T00:00:00.000'));

    final characters = await repository.list(kind: SettingCardKind.character);

    expect(characters.map((c) => c.id), <String>['b', 'c']);
  });

  test('soft delete hides the card unless includeDeleted is set', () async {
    await repository.save(card('c1'));

    await repository.softDelete('c1', deletedAt: '2026-05-01T00:00:00.000');

    expect(await repository.list(), isEmpty);
    final deleted = await repository.list(includeDeleted: true);
    expect(deleted, hasLength(1));
    expect(deleted.single.isDeleted, isTrue);
    expect(deleted.single.updatedAt, '2026-05-01T00:00:00.000');
  });

  test('findLegacyId resolves the migrated row', () async {
    await repository
        .save(card('res_legacy_worldview_presets_w1', legacyId: 'w1'));

    final loaded = await repository.findLegacyId(
      'w1',
      kind: SettingCardKind.worldview,
    );
    expect(loaded, isNull, reason: 'kind must narrow the lookup');

    final anyKind = await repository.findLegacyId('w1');
    expect(anyKind!.id, 'res_legacy_worldview_presets_w1');
  });

  test('damaged metadata_json degrades to an empty map, body survives',
      () async {
    await db.insert('setting_cards', <String, Object?>{
      'id': 'broken',
      'kind': 'character',
      'name': '坏元数据',
      'content': '正文仍在',
      'status': 'draft',
      'origin': 'native',
      'metadata_json': '{not-json',
      'created_at': '2026-01-01T00:00:00.000',
      'updated_at': '2026-01-01T00:00:00.000',
    });

    final loaded = await repository.findById('broken');

    expect(loaded, isNotNull);
    expect(loaded!.metadata, isEmpty);
    expect(loaded.content, '正文仍在');
  });
}
