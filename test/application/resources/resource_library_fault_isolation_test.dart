import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/setting_card_repository_impl.dart';

/// Fault isolation of the card-only Resource Library read path.
///
/// The library is now a single `setting_cards` enumeration. One card whose
/// metadata or body cannot be interpreted must never take the whole list down;
/// only a genuine table/database level failure may surface as a library error.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late ProviderContainer container;
  late SettingCardRepositoryImpl cards;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_lib_isolation_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    container = ProviderContainer();
    cards = SettingCardRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    container.dispose();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ResourceLibraryRuntime library() =>
      container.read(resourceLibraryRuntimeProvider);

  Future<void> seedCard({
    required String id,
    required SettingCardKind kind,
    required String name,
    required String content,
    String summary = '',
  }) =>
      cards.save(SettingCard(
        id: id,
        kind: kind,
        name: name,
        summary: summary,
        content: content,
        createdAt: '2026-01-01T00:00:00',
        updatedAt: '2026-01-01T00:00:00',
      ));

  test('all card-backed resources load successfully', () async {
    await seedCard(
        id: 'card_a',
        kind: SettingCardKind.worldview,
        name: 'A',
        content: 'A 内容');
    await seedCard(
        id: 'card_b',
        kind: SettingCardKind.character,
        name: 'B',
        content: 'B 内容');
    await seedCard(
        id: 'card_c', kind: SettingCardKind.npc, name: 'C', content: 'C 内容');

    final items = await library().load(ResourceLibraryMode.adventure);

    expect(items, hasLength(3));
    expect(items.every((item) => item.isSettingCard), isTrue);
    expect(items.every((item) => item.isConsumable), isTrue);
  });

  test('a corrupt metadata row degrades without breaking the list', () async {
    await seedCard(
        id: 'card_ok',
        kind: SettingCardKind.worldview,
        name: '正常',
        content: '正常内容');
    final db = await DatabaseService.database;
    await db.insert('setting_cards', <String, Object?>{
      'id': 'card_bad_meta',
      'kind': 'character',
      'name': '损坏元数据',
      'summary': '',
      'content': '正文仍然可读',
      'metadata_json': '{not valid json',
      'created_at': '2026-01-01T00:00:00',
      'updated_at': '2026-01-01T00:00:00',
    });

    final items = await library().load(ResourceLibraryMode.adventure);

    expect(items, hasLength(2));
    // The damaged metadata degrades to an empty map instead of hiding the card.
    final degraded = await cards.findById('card_bad_meta');
    expect(degraded, isNotNull);
    expect(degraded!.metadata, isEmpty);
    // The body — the part the user cares about — is still listed and usable.
    final bad = items.firstWhere((item) => item.id == 'card_bad_meta');
    expect(bad.isConsumable, isTrue);
    expect(bad.name, '损坏元数据');
    expect(items.any((item) => item.id == 'card_ok'), isTrue);
  });

  test('an unparseable card body still lists verbatim', () async {
    await seedCard(
        id: 'card_ok',
        kind: SettingCardKind.worldview,
        name: '正常',
        content: '正常内容');
    final db = await DatabaseService.database;
    await db.insert('setting_cards', <String, Object?>{
      'id': 'card_bad_body',
      'kind': 'npc',
      'name': '损坏正文',
      'summary': '',
      'content': '{not valid json',
      'metadata_json': '{}',
      'created_at': '2026-01-01T00:00:00',
      'updated_at': '2026-01-01T00:00:00',
    });

    final items = await library().load(ResourceLibraryMode.adventure);

    expect(items, hasLength(2));
    final bad = await cards.findById('card_bad_body');
    expect(bad!.content, '{not valid json');
    expect(items.firstWhere((item) => item.id == 'card_bad_body').isConsumable,
        isTrue);
  });

  test('an empty-body card is listed as non-consumable', () async {
    await seedCard(
        id: 'card_empty',
        kind: SettingCardKind.character,
        name: '空卡',
        content: '');

    final items = await library().load(ResourceLibraryMode.adventure);

    expect(items, hasLength(1));
    expect(items.single.isConsumable, isFalse);
  });

  test('a fatal table-level failure propagates as a library error', () async {
    await seedCard(
        id: 'card_a',
        kind: SettingCardKind.worldview,
        name: 'A',
        content: 'A 内容');
    final db = await DatabaseService.database;
    await db.execute('DROP TABLE setting_cards');

    expect(
      () => library().load(ResourceLibraryMode.adventure),
      throwsA(anything),
    );
  });
}
