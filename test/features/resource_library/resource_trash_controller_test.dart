import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_trash_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_trash_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/controllers/resource_trash_controller.dart';

void main() {
  group('ResourceTrashController', () {
    test('should keep the newest result when refreshes complete out of order',
        () async {
      final runtime = _ControlledTrashRuntime();
      final controller = ResourceTrashController(runtime: runtime);
      addTearDown(controller.dispose);

      final firstLoad = controller.load();
      await _waitForListCalls(runtime, 1);
      final secondLoad = controller.refresh();
      await _waitForListCalls(runtime, 2);

      runtime.listCalls[1].complete([_item('new')]);
      await secondLoad;
      expect(controller.state.items.single.trashId, 'new');

      runtime.listCalls[0].complete([_item('old')]);
      await firstLoad;
      expect(controller.state.items.single.trashId, 'new');
      expect(controller.state.status, ResourceTrashViewStatus.ready);
    });

    test('should ignore an older refresh error after a newer result', () async {
      final runtime = _ControlledTrashRuntime();
      final controller = ResourceTrashController(runtime: runtime);
      addTearDown(controller.dispose);

      final firstLoad = controller.load();
      await _waitForListCalls(runtime, 1);
      final secondLoad = controller.refresh();
      await _waitForListCalls(runtime, 2);

      runtime.listCalls[1].complete([_item('current')]);
      await secondLoad;
      runtime.listCalls[0].completeError(StateError('旧请求失败'));
      await firstLoad;

      expect(controller.state.status, ResourceTrashViewStatus.ready);
      expect(controller.state.items.single.trashId, 'current');
      expect(controller.state.errorMessage, isEmpty);
    });

    test('should invalidate an in-flight load when restore starts', () async {
      final runtime = _ControlledTrashRuntime();
      final controller = ResourceTrashController(runtime: runtime);
      addTearDown(controller.dispose);

      final load = controller.load();
      await _waitForListCalls(runtime, 1);
      final restore = controller.restore('trash_old');
      await _waitForListCalls(runtime, 2);

      runtime.listCalls[1].complete([_item('remaining')]);
      await restore;
      runtime.listCalls[0].complete([_item('stale')]);
      await load;

      expect(controller.state.items.single.trashId, 'remaining');
      expect(controller.state.statusMessage, '已恢复');
    });

    test('should not notify or publish a late result after dispose', () async {
      final runtime = _ControlledTrashRuntime();
      final controller = ResourceTrashController(runtime: runtime);
      var notifications = 0;
      controller.addListener(() => notifications++);

      final load = controller.load();
      await _waitForListCalls(runtime, 1);
      expect(notifications, 1);
      controller.dispose();

      runtime.listCalls.single.complete([_item('late')]);
      await load;

      expect(notifications, 1);
      expect(controller.state.items, isEmpty);
      expect(runtime.isDisposed, isTrue);
    });
  });
}

Future<void> _waitForListCalls(
  _ControlledTrashRuntime runtime,
  int count,
) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    if (runtime.listCalls.length >= count) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Expected $count list calls, got ${runtime.listCalls.length}');
}

ResourceTrashItem _item(String id) => ResourceTrashItem(
      trashId: id,
      resourceId: 'resource_$id',
      title: id,
      kindLabel: '段落',
      reasonLabel: '用户删除',
      deletedAtLabel: '2026-09-18 10:00',
      expiresAtLabel: '2026-10-18 10:00',
      isRestored: false,
    );

final class _ControlledTrashRuntime implements ResourceTrashRuntime {
  final List<Completer<List<ResourceTrashItem>>> listCalls = [];
  bool isDisposed = false;

  @override
  Future<List<ResourceTrashItem>> list() {
    final completer = Completer<List<ResourceTrashItem>>();
    listCalls.add(completer);
    return completer.future;
  }

  @override
  Future<int> purgeExpired() async => 0;

  @override
  Future<TrashRestoreSummary> restore(String trashId) async =>
      const TrashRestoreSummary(
        alreadyRestored: false,
        usedFallback: false,
        message: '已恢复',
      );

  @override
  Future<int> permanentDelete(String trashId) async => 1;

  @override
  void dispose() {
    isDisposed = true;
  }
}
