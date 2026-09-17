import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_repository.dart';
import 'package:lt_dialogue/application/resources/resource_capacity_service.dart';
import 'package:lt_dialogue/domain/resources/resource_capacity.dart';
import 'package:lt_dialogue/domain/resources/resource_compression.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds a real tree through the production writer, so capacity is measured
/// against exactly the storage shape Phase 1 freezes.
Future<ResourceId> _createTree(
  Database db, {
  required ResourceId id,
  required ResourceType type,
  required String name,
  required List<int> sectionSizes,
  int sectionCount = 1,
  String filler = '赤',
}) async {
  final repository = ResourceTreeRepositoryImpl(getDb: () async => db);
  return repository.createResourceTree(
    ResourceTreeDraft(
      id: id,
      type: type,
      name: name,
      summary: 'summary',
      sections: [
        for (var s = 0; s < sectionCount; s++)
          ResourceTreeSectionDraft(
            title: '第$s章',
            parts: [
              for (var p = 0; p < sectionSizes.length; p++)
                ResourceTreePartDraft(
                  title: '部件$p',
                  content: filler * sectionSizes[p],
                ),
            ],
          ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lt_phase8_capacity_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ResourceCapacityService — small resource', () {
    test('measures characters, counts and status', () async {
      final db = await DatabaseService.database;
      final id = await _createTree(
        db,
        id: const ResourceId('res_small'),
        type: ResourceType.character,
        name: '小角色',
        sectionSizes: [10, 20, 30],
        sectionCount: 2,
      );

      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );
      final snapshot = await service.measure(id);

      // 2 sections × (10 + 20 + 30) characters.
      expect(snapshot.totalCharacters, 120);
      expect(snapshot.sectionCount, 2);
      expect(snapshot.partCount, 6);
      expect(snapshot.status, CapacityStatus.normal);
      expect(snapshot.estimatedTokens,
          ResourceCapacityMath.tokensForCharacters(120));
      expect(snapshot.measuredAt, isNotNull);
    });

    test('excludes soft-deleted nodes', () async {
      final db = await DatabaseService.database;
      final id = await _createTree(
        db,
        id: const ResourceId('res_deleted'),
        type: ResourceType.character,
        name: '含删除',
        sectionSizes: [10, 10],
      );
      final repository = ResourceTreeRepositoryImpl(getDb: () async => db);
      final sections = await repository.readSections(id);
      final state = await repository.readNodeState(sections.first.id);
      await repository.softDeleteNode(
        id: sections.first.id,
        expectedUpdatedAt: state!.updatedAt,
      );

      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );
      final snapshot = await service.measure(id);
      expect(snapshot.totalCharacters, 0);
      expect(snapshot.sectionCount, 0);
      expect(snapshot.partCount, 0);
    });

    test('reports archived characters separately from active ones', () async {
      final db = await DatabaseService.database;
      final id = await _createTree(
        db,
        id: const ResourceId('res_archived'),
        type: ResourceType.worldview,
        name: '含归档',
        sectionSizes: [100, 40],
      );
      final repository = ResourceTreeRepositoryImpl(getDb: () async => db);
      final sections = await repository.readSections(id);
      final parts = await repository.readParts(sections.first.id);
      final state = await repository.readNodeState(parts.first.id);
      await db.update(
        'resource_parts',
        {'status': 'archived'},
        where: 'id = ?',
        whereArgs: [parts.first.id.value],
      );
      expect(state, isNotNull);

      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );
      final snapshot = await service.measure(id);
      expect(snapshot.totalCharacters, 140);
      expect(snapshot.archivedCharacters, 100);
      expect(snapshot.activeCharacters, 40);
      expect(snapshot.archiveSize, 100);
    });
  });

  group('ResourceCapacityService — large resource', () {
    test('measures a 400-Part resource correctly in one pass', () async {
      final db = await DatabaseService.database;
      const sectionCount = 40;
      const partsPerSection = 10;
      const partLength = 80;
      final id = await _createTree(
        db,
        id: const ResourceId('res_large'),
        type: ResourceType.worldview,
        name: '长篇小说世界观',
        sectionSizes: List<int>.filled(partsPerSection, partLength),
        sectionCount: sectionCount,
      );

      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );
      final snapshot = await service.measure(id);

      expect(snapshot.sectionCount, sectionCount);
      expect(snapshot.partCount, sectionCount * partsPerSection);
      expect(
        snapshot.totalCharacters,
        sectionCount * partsPerSection * partLength,
      );

      final sections = await service.sections(id);
      expect(sections, hasLength(sectionCount));
      expect(
        sections.every(
            (section) => section.characters == partsPerSection * partLength),
        isTrue,
      );
      expect(sections.every((section) => section.isComplete), isTrue);
      expect(
        sections.every((section) => section.isCompressionCandidate),
        isTrue,
      );
    });

    test('measureAll returns every resource with a bounded statement count',
        () async {
      final db = await DatabaseService.database;
      for (var i = 0; i < 12; i++) {
        await _createTree(
          db,
          id: ResourceId('res_bulk_$i'),
          type: i.isEven ? ResourceType.worldview : ResourceType.character,
          name: '资源$i',
          sectionSizes: [10, 10],
          sectionCount: 2,
        );
      }

      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );
      final all = await service.measureAll();
      expect(all, hasLength(12));
      expect(
        all.fold<int>(0, (sum, snapshot) => sum + snapshot.totalCharacters),
        12 * 40,
      );

      final worldview = await service.measureAll(type: ResourceType.worldview);
      expect(worldview, hasLength(6));
      expect(
        worldview.every((snapshot) => snapshot.type == ResourceType.worldview),
        isTrue,
      );
    });

    test('statement count is independent of tree size (no N+1)', () async {
      final db = await DatabaseService.database;
      final smallId = await _createTree(
        db,
        id: const ResourceId('res_stmt_small'),
        type: ResourceType.worldview,
        name: '小',
        sectionSizes: [10, 10],
        sectionCount: 1,
      );
      final largeId = await _createTree(
        db,
        id: const ResourceId('res_stmt_large'),
        type: ResourceType.worldview,
        name: '大',
        sectionSizes: const [50, 50, 50, 50, 50, 50, 50, 50, 50, 50],
        sectionCount: 40,
      );

      final smallCounter = _CountingDatabase(db);
      final smallService = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(
          getDb: () async => smallCounter,
        ),
      );
      await smallService.measure(smallId);
      await smallService.sections(smallId);
      final smallStatements = smallCounter.statements;

      final largeCounter = _CountingDatabase(db);
      final largeService = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(
          getDb: () async => largeCounter,
        ),
      );
      final snapshot = await largeService.measure(largeId);
      await largeService.sections(largeId);
      final largeStatements = largeCounter.statements;

      expect(snapshot.sectionCount, 40);
      expect(snapshot.partCount, 400);
      expect(
        largeStatements,
        smallStatements,
        reason: 'a 400-Part tree must cost exactly as many statements as a '
            '2-Part tree; anything else is an N+1 measurement',
      );
      expect(smallStatements, lessThanOrEqualTo(8));
    });

    test('the measurement path never selects every column', () {
      final source = File(
        'lib/application/resources/resource_capacity_repository.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'SELECT\s+\*\s+FROM', caseSensitive: false).hasMatch(source),
        isFalse,
        reason: 'capacity must read named columns only',
      );
      expect(source.contains('GROUP BY'), isTrue,
          reason: 'aggregation must happen in SQLite, not by reading rows into '
              'Dart one section at a time');
    });
  });

  group('capacity cache', () {
    test('persists a measurement and reads it back cheaply', () async {
      final db = await DatabaseService.database;
      final id = await _createTree(
        db,
        id: const ResourceId('res_cache'),
        type: ResourceType.character,
        name: '缓存资源',
        sectionSizes: [100],
      );
      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );

      expect(await service.readCached(id), isNull,
          reason: 'never measured means no cached value');

      final measured = await service.measure(id);
      final cached = await service.readCached(id);
      expect(cached, isNotNull);
      expect(cached!.totalCharacters, measured.totalCharacters);
      expect(cached.partCount, measured.partCount);
      expect(cached.status, measured.status);
      expect(cached.measuredAt, isNotNull);
    });

    test('a cached value is advisory and a re-measure sees new content',
        () async {
      final db = await DatabaseService.database;
      final id = await _createTree(
        db,
        id: const ResourceId('res_cache_edit'),
        type: ResourceType.character,
        name: '缓存编辑',
        sectionSizes: [100],
      );
      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );
      await service.measure(id);

      final repository = ResourceTreeRepositoryImpl(getDb: () async => db);
      final sections = await repository.readSections(id);
      final parts = await repository.readParts(sections.first.id);
      final state = await repository.readNodeState(parts.first.id);
      await db.update(
        'resource_parts',
        {'content': '赤' * 6000},
        where: 'id = ?',
        whereArgs: [parts.first.id.value],
      );
      expect(state, isNotNull);

      expect((await service.readCached(id))!.totalCharacters, 100,
          reason: 'the cache still holds the previous measurement');

      final remeasured = await service.measure(id);
      expect(remeasured.totalCharacters, 6000);
      expect(remeasured.status, CapacityStatus.elastic);
      expect((await service.readCached(id))!.totalCharacters, 6000);
    });
  });

  group('trigger evaluation through the service', () {
    test('classifies and triggers at every boundary', () async {
      final db = await DatabaseService.database;
      final id = await _createTree(
        db,
        id: const ResourceId('res_trigger'),
        type: ResourceType.character,
        name: '触发',
        sectionSizes: [100],
      );
      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );
      final snapshot = await service.measure(id);

      expect(
        service.evaluateResource(snapshot).shouldCompress,
        isFalse,
      );
      expect(
        service
            .evaluateResource(snapshot.copyWith(
              totalCharacters: 6001,
              status: CapacityStatus.overflow,
            ))
            .reason,
        CompressionTriggerReason.capacityOverflow,
      );
      expect(
        service
            .evaluateContext(ResourceLimitsForTest.contextTrigger + 1)
            .reason,
        CompressionTriggerReason.contextBudgetExceeded,
      );
    });

    test('compressionTargets returns only complete large sections', () async {
      final db = await DatabaseService.database;
      final id = await _createTree(
        db,
        id: const ResourceId('res_targets'),
        type: ResourceType.worldview,
        name: '目标',
        sectionSizes: [2000],
        sectionCount: 3,
      );
      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );
      final targets = await service.compressionTargets(id);
      expect(targets, hasLength(3));
      expect(targets.first.characters, 2000);
    });
  });

  group('ResourceCapacityRepository errors', () {
    test('measuring a missing resource throws a domain error', () async {
      final db = await DatabaseService.database;
      final service = ResourceCapacityService(
        repository: ResourceCapacityRepositoryImpl(getDb: () async => db),
      );
      expect(
        () => service.measure(const ResourceId('res_missing')),
        throwsA(isA<ResourceCapacityException>()),
      );
    });
  });
}

/// Local mirror of the context trigger constant, kept out of production code
/// so this test states the boundary explicitly.
abstract final class ResourceLimitsForTest {
  static const int contextTrigger = 8000;
}

/// Counts the SQL statements a repository issues.
///
/// Only the three statements the capacity path uses are forwarded explicitly;
/// declaring [noSuchMethod] lets the remaining `Database` members stay
/// unimplemented, and they are never called by this code path.
final class _CountingDatabase implements Database {
  _CountingDatabase(this._inner);

  final Database _inner;
  int statements = 0;

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    statements++;
    return _inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    statements++;
    return _inner.rawQuery(sql, arguments);
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    ConflictAlgorithm? conflictAlgorithm,
    String? where,
    List<Object?>? whereArgs,
  }) {
    statements++;
    return _inner.update(
      table,
      values,
      conflictAlgorithm: conflictAlgorithm,
      where: where,
      whereArgs: whereArgs,
    );
  }

  @override
  Future<void> close() => _inner.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
