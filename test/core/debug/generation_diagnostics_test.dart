import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/debug/generation_diagnostics.dart';

void main() {
  group('GenerationDiagnostics heartbeat lifecycle', () {
    late GenerationDiagnostics diagnostics;
    var elapsed = Duration.zero;
    late bool printingWasEnabled;
    setUp(() {
      elapsed = Duration.zero;
      diagnostics = GenerationDiagnostics.forTesting(elapsed: () => elapsed);
      printingWasEnabled = GenerationDiagnostics.printingEnabled;
      GenerationDiagnostics.printingEnabled = false;
    });
    tearDown(() {
      diagnostics.stopUiHeartbeat();
      diagnostics.stopUiHeartbeat();
      diagnostics.resetForTesting();
      GenerationDiagnostics.printingEnabled = printingWasEnabled;
    });
    Future<void> advance(WidgetTester tester, int milliseconds) async {
      elapsed += Duration(milliseconds: milliseconds);
      await tester.pump(Duration(milliseconds: milliseconds));
    }

    void heartbeatTest(
        String description, Future<void> Function(WidgetTester) body) {
      testWidgets(description, (tester) async {
        try {
          await body(tester);
        } finally {
          // Widget test timer invariants run before normal tearDown callbacks.
          diagnostics.stopUiHeartbeat();
          diagnostics.stopUiHeartbeat();
          diagnostics.resetForTesting();
        }
      });
    }

    heartbeatTest('should reset baseline after an unobserved stopped interval',
        (tester) async {
      diagnostics.startUiHeartbeat(interval: const Duration(milliseconds: 20));
      await advance(tester, 20);
      expect(diagnostics.uiHeartbeatTicks, 1);
      diagnostics.stopUiHeartbeat();
      await advance(tester, 150);
      expect(diagnostics.uiHeartbeatTicks, 1);
      diagnostics.startUiHeartbeat(interval: const Duration(milliseconds: 20));
      await advance(tester, 20);
      expect(diagnostics.uiHeartbeatTicks, 2);
      expect(diagnostics.dumpReasons, isEmpty);
    });
    heartbeatTest(
        'should retain the first owner interval and detect active delay',
        (tester) async {
      diagnostics.startUiHeartbeat(interval: const Duration(milliseconds: 20));
      await advance(tester, 20);
      diagnostics.startUiHeartbeat(
          interval: const Duration(milliseconds: 1000));
      // Simulate a monotonic clock jump without running any queued timer tick.
      elapsed += const Duration(milliseconds: 100);
      await advance(tester, 20);
      expect(diagnostics.dumpReasons, hasLength(1));
      expect(diagnostics.dumpReasons.single, contains('UI_HEARTBEAT_GAP'));
      expect(diagnostics.dumpReasons.single,
          isNot(contains('main isolate was blocked')));
      diagnostics.stopUiHeartbeat();
      await advance(tester, 20);
      expect(diagnostics.uiHeartbeatTicks, 3,
          reason: 'the first owner still observes ticks');
      diagnostics.stopUiHeartbeat();
      await advance(tester, 100);
      expect(diagnostics.uiHeartbeatTicks, 3);
    });
    heartbeatTest('should clean up all owned timers in the test reset',
        (tester) async {
      diagnostics.startUiHeartbeat(interval: const Duration(milliseconds: 20));
      diagnostics.startUiHeartbeat();
      await advance(tester, 20);
      diagnostics.resetForTesting();
      await advance(tester, 100);
      expect(diagnostics.uiHeartbeatTicks, 0);
      expect(diagnostics.dumpReasons, isEmpty);
      diagnostics.startUiHeartbeat(interval: const Duration(milliseconds: 20));
      await advance(tester, 20);
      expect(diagnostics.uiHeartbeatTicks, 1);
    });
    heartbeatTest(
        'should keep long streaming progress observable without declaring a deadlock',
        (tester) async {
      diagnostics.beginRun('long-stream');
      diagnostics.startWatchdog(
          interval: const Duration(seconds: 1),
          stallThreshold: const Duration(seconds: 10));
      for (var index = 0; index < 30; index++) {
        diagnostics.runtimeHeartbeat('part.sseChunk');
        await advance(tester, 1000);
      }
      expect(diagnostics.runtimeHeartbeatSeq, 30);
      expect(diagnostics.dumpReasons, isEmpty);
      diagnostics.endRun('long-stream');
    });
    heartbeatTest('should report a real delay even on the first owned tick',
        (tester) async {
      diagnostics.startUiHeartbeat(interval: const Duration(milliseconds: 20));
      elapsed += const Duration(milliseconds: 100);
      await advance(tester, 20);
      expect(diagnostics.dumpReasons, hasLength(1));
      expect(diagnostics.dumpReasons.single, contains('UI_HEARTBEAT_GAP'));
      expect(diagnostics.dumpReasons.single,
          isNot(contains('main isolate was blocked')));
    });
    heartbeatTest('should label stopped observation as unobserved',
        (tester) async {
      diagnostics.startUiHeartbeat(interval: const Duration(milliseconds: 20));
      await advance(tester, 20);
      diagnostics.stopUiHeartbeat();
      await advance(tester, 150);
      final report = diagnostics.dump(reason: 'inspection');
      expect(report, contains('owners=0, state=unobserved'));
      expect(diagnostics.dumpReasons, ['inspection']);
    });
  });
}
