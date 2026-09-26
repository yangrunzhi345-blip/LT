import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/refresh/page_refresh_controller.dart';

void main() {
  group('PageRefreshController lifecycle & disposal safety', () {
    late PageRefreshController controller;

    setUp(() {
      controller = PageRefreshController();
    });

    test('normal lifecycle: register, refresh success, and notifyListeners',
        () async {
      final owner = Object();
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.register(owner, () async => const PageRefreshResult.success());
      expect(notifyCount, 1);
      expect(controller.isAvailable, isTrue);

      final refreshFuture = controller.refresh();
      expect(controller.isRefreshing, isTrue);
      expect(notifyCount, 2);

      final result = await refreshFuture;
      expect(result.isSuccess, isTrue);
      expect(controller.status, PageRefreshStatus.success);
      expect(controller.isRefreshing, isFalse);
      expect(controller.lastRefreshedAt, isNotNull);
      expect(notifyCount, 3);
    });

    test(
        'dispose while refresh is in flight clears references and prevents late notifyListeners',
        () async {
      final owner = Object();
      final completer = Completer<PageRefreshResult>();
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.register(owner, () => completer.future);
      expect(controller.isAvailable, isTrue);
      expect(notifyCount, 1);

      // Start refresh
      final refreshFuture = controller.refresh();
      expect(controller.isRefreshing, isTrue);
      expect(notifyCount, 2);

      // Dispose while refresh is still pending
      expect(() => controller.dispose(), returnsNormally);
      expect(controller.isDisposed, isTrue);
      expect(controller.isAvailable, isFalse);

      // Complete the pending callback after disposal
      completer.complete(const PageRefreshResult.success());
      final result = await refreshFuture;
      expect(result.isSuccess, isTrue);

      // Must not invoke notifyListeners on disposed controller (would throw Flutter error)
      expect(notifyCount, 2);
    });

    test('dispose after late async callback completes safely without throwing',
        () async {
      final owner = Object();
      final completer = Completer<PageRefreshResult>();
      controller.register(owner, () => completer.future);

      final refreshFuture = controller.refresh();

      // Dispose immediately
      controller.dispose();

      // Now complete with error/failure
      completer.complete(const PageRefreshResult.failure('late error'));
      final result = await refreshFuture;
      expect(result.isSuccess, isFalse);
      expect(result.error, 'late error');
      // No exception thrown
    });

    test('calling refresh after dispose returns failure and does not notify',
        () async {
      final owner = Object();
      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.register(owner, () async => const PageRefreshResult.success());
      expect(notifyCount, 1);

      controller.dispose();
      expect(controller.isDisposed, isTrue);

      final result = await controller.refresh();
      expect(result.isSuccess, isFalse);
      expect(result.error, 'disposed');
      expect(notifyCount, 1);
    });

    test('calling register after dispose safely ignores registration', () {
      controller.dispose();
      expect(controller.isDisposed, isTrue);

      // Should not throw or register callback
      expect(
          () => controller.register(
              Object(), () async => const PageRefreshResult.success()),
          returnsNormally);
      expect(controller.isAvailable, isFalse);
    });

    test('calling unregister after dispose safely returns without throwing',
        () {
      final owner = Object();
      controller.register(owner, () async => const PageRefreshResult.success());
      controller.dispose();

      expect(() => controller.unregister(owner), returnsNormally);
    });
  });
}
