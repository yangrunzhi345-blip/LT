import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/controllers/resource_library_controller.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';

final class _FakeLibraryRuntime implements ResourceLibraryRuntime {
  _FakeLibraryRuntime(this.items);

  final List<ResourceLibraryItem> items;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async =>
      items;

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async =>
      const ResourceOperationResult.success(message: '已移入回收站');

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      items.first.id;
}

void main() {
  final items = <ResourceLibraryItem>[
    const ResourceLibraryItem(
      id: 'w1',
      type: ResourceType.worldview,
      name: '银月大陆',
      summary: '贸易海港与古老法则',
      updatedAt: '2026-09-18',
      status: ResourceDisplayStatus.ready,
      isStudioAvailable: true,
    ),
    const ResourceLibraryItem(
      id: 'c1',
      type: ResourceType.character,
      name: '林舟',
      summary: '守夜人',
      updatedAt: '2026-09-17',
      status: ResourceDisplayStatus.saved,
      isStudioAvailable: true,
    ),
  ];

  group('ResourceLibraryController', () {
    late ResourceLibraryController controller;

    setUp(() {
      controller = ResourceLibraryController(
        runtime: _FakeLibraryRuntime(items),
        mode: ResourceLibraryMode.adventure,
      );
    });

    tearDown(() => controller.dispose());

    test('should filter and search the unified list', () async {
      await controller.load();
      controller.filter(ResourceLibraryFilter.worldview);
      expect(controller.state.visibleItems.map((item) => item.id), ['w1']);
      controller.search('海港');
      expect(controller.state.visibleItems.map((item) => item.id), ['w1']);
      controller.search('不存在');
      expect(controller.state.visibleItems, isEmpty);
    });

    test('should expose a user-facing error state when loading fails',
        () async {
      final failing = ResourceLibraryController(
        runtime: _FailingRuntime(),
        mode: ResourceLibraryMode.adventure,
      );
      addTearDown(failing.dispose);
      await failing.load();
      expect(failing.state.status, ResourceLibraryStatus.error);
      expect(failing.state.errorMessage, '资源库加载失败，请重试');
    });

    test('should convert a thrown trash operation into a failure result',
        () async {
      final failing = ResourceLibraryController(
        runtime: _FailingRuntime(),
        mode: ResourceLibraryMode.adventure,
      );
      addTearDown(failing.dispose);

      final result = await failing.moveToTrash(items.first);

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('test'));
    });

    test('should ignore stale loads and completions after disposal', () async {
      final runtime = _SequencedLibraryRuntime();
      final raced = ResourceLibraryController(
        runtime: runtime,
        mode: ResourceLibraryMode.adventure,
      );
      final first = raced.load();
      final second = raced.load();
      runtime.complete(0, [items[0]]);
      await first;
      expect(raced.state.items, isEmpty);
      runtime.complete(1, [items[1]]);
      await second;
      expect(raced.state.items.single.id, 'c1');

      final late = raced.load();
      raced.dispose();
      runtime.complete(2, [items[0]]);
      await late;
      expect(raced.state.items.single.id, 'c1');
    });
  });
}

final class _SequencedLibraryRuntime implements ResourceLibraryRuntime {
  final List<Completer<List<ResourceLibraryItem>>> _loads = [];

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) {
    final completer = Completer<List<ResourceLibraryItem>>();
    _loads.add(completer);
    return completer.future;
  }

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async =>
      const ResourceOperationResult.success(message: '已移入回收站');

  void complete(int index, List<ResourceLibraryItem> value) {
    _loads[index].complete(value);
  }

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      'created';
}

final class _FailingRuntime implements ResourceLibraryRuntime {
  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async {
    throw StateError('test');
  }

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async {
    throw StateError('test');
  }

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async {
    throw StateError('test');
  }
}
