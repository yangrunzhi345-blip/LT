import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/assembly_readiness_repository.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

import '../../helpers/phase10_fixture.dart';

/// Fault isolation of the Resource Library read path against a real SQLite
/// tree/readiness stack.
///
/// One bad resource must never take the whole list down: a per-resource
/// lifecycle fault becomes a terminal「校验失败」item, while only a genuine
/// table/database level failure is allowed to surface as a library error.
void main() {
  late Phase10Fixture fixture;
  late ProviderContainer container;

  setUp(() async {
    fixture = Phase10Fixture();
    await fixture.setUp(prefix: 'lt_lib_isolation_');
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await fixture.tearDown();
  });

  ResourceLibraryRuntime library() =>
      container.read(resourceLibraryRuntimeProvider);

  Future<void> prepare(ResourceId id) => fixture.coordinator.prepare(id);

  test('all-ready resources load successfully', () async {
    final a = await fixture.createWorldview('res_a', [
      ['A 内容']
    ]);
    final b = await fixture.createWorldview('res_b', [
      ['B 内容']
    ]);
    final c = await fixture.createWorldview('res_c', [
      ['C 内容']
    ]);
    for (final id in [a, b, c]) {
      await prepare(id);
    }

    final items = await library().load(ResourceLibraryMode.adventure);

    expect(items, hasLength(3));
    expect(
      items
          .every((item) => item.lifecycleState == ResourceLifecycleState.ready),
      isTrue,
    );
    expect(items.every((item) => item.isConsumable), isTrue);
  });

  test('one failed readiness still lists every resource', () async {
    final a = await fixture.createWorldview('res_a', [
      ['A 内容']
    ]);
    final b = await fixture.createWorldview('res_b', [
      ['B 内容']
    ]);
    final c = await fixture.createWorldview('res_c', [
      ['C 内容']
    ]);
    await prepare(a);
    await prepare(c);
    await fixture.db.transaction((txn) {
      return fixture.readinessRepository.writeInTransaction(
        txn,
        AssemblyReadinessRecord(
          resourceId: b.value,
          state: ReadinessState.failed,
          attemptToken: 'attempt_terminal',
        ),
      );
    });

    final items = await library().load(ResourceLibraryMode.adventure);

    expect(items, hasLength(3));
    final failed = items
        .where((item) => item.lifecycleState == ResourceLifecycleState.failed);
    expect(failed, hasLength(1));
    expect(failed.single.id, b.value);
    expect(failed.single.status, ResourceDisplayStatus.optimizationFailed);
    expect(failed.single.isConsumable, isFalse);
    expect(
      items.where((item) => item.isConsumable),
      hasLength(2),
    );
  });

  test('an unreadable per-resource lifecycle is isolated, not escalated',
      () async {
    final a = await fixture.createWorldview('res_a', [
      ['A 内容']
    ]);
    final b = await fixture.createWorldview('res_b', [
      ['B 内容']
    ]);
    final c = await fixture.createWorldview('res_c', [
      ['C 内容']
    ]);
    for (final id in [a, b, c]) {
      await prepare(id);
    }
    // A legacy / unknown readiness state makes the projection for `b`
    // unrepresentable. It must degrade to one failed item, not fail the list.
    await fixture.db.rawUpdate(
      "UPDATE resource_assembly_readiness SET state = 'weird_legacy_state' "
      'WHERE resource_id = ?',
      <Object?>[b.value],
    );

    final items = await library().load(ResourceLibraryMode.adventure);

    expect(items, hasLength(3));
    final failed = items.firstWhere((item) => item.id == b.value);
    expect(failed.lifecycleState, ResourceLifecycleState.failed);
    expect(failed.status, ResourceDisplayStatus.optimizationFailed);
    expect(failed.isConsumable, isFalse);
    expect(
      items.where((item) => item.isConsumable),
      hasLength(2),
    );
  });

  test('a legacy resource with no generation session does not break the list',
      () async {
    await fixture.createWorldview('res_legacy', [
      ['旧资源']
    ]);

    final items = await library().load(ResourceLibraryMode.adventure);

    expect(items, hasLength(1));
    expect(items.single.lifecycleState, isNot(ResourceLifecycleState.failed));
  });

  test('an unmappable stored row does not fail the enumeration', () async {
    await fixture.createWorldview('res_ok', [
      ['正常内容']
    ]);
    await fixture.db.insert('resources', <String, Object?>{
      'id': 'res_corrupt',
      'type': 'worldview',
      'name': '损坏资源',
      'summary': '',
      'status': 'draft',
      'metadata_json': '{not valid json',
      'schema_version': 1,
      'created_at': '2026-01-01T00:00:00',
      'updated_at': '2026-01-01T00:00:00',
    });

    final items = await library().load(ResourceLibraryMode.adventure);

    // The valid resource still loads; the unmappable row cannot be represented
    // and is skipped rather than aborting the whole library.
    expect(items.any((item) => item.id == 'res_ok'), isTrue);
  });

  test('a fatal table-level failure propagates as a library error', () async {
    await fixture.createWorldview('res_a', [
      ['A 内容']
    ]);
    await fixture.db.execute('DROP TABLE worldview_presets');

    expect(
      () => library().load(ResourceLibraryMode.adventure),
      throwsA(anything),
    );
  });
}
