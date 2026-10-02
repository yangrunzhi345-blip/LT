import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

/// Top-level workbench content pages whose chrome must stay convergent.
const List<String> _workbenchPages = <String>[
  'lib/features/resource_library/presentation/screens/resource_library_screen.dart',
  'lib/features/adventure/presentation/templates/screens/preset_scenes_screen.dart',
];

/// Guard: workbench page chrome is a shared foundation, not per-feature copies.
///
/// This targets *page back / return navigation* specifically — `FilledButton`
/// and `FilledButton.tonal` remain legitimate for ordinary business actions
/// (e.g. the preset card's quick-start button), so the guard only fails when a
/// filled CTA is used as the return control.
void main() {
  group('Workbench page chrome guard', () {
    test('top-level pages reuse the shared header and back action', () {
      for (final path in _workbenchPages) {
        final source = File(path).readAsStringSync();
        expect(source.contains('WorkbenchPageHeader'), isTrue,
            reason: '$path must render WorkbenchPageHeader');
        expect(source.contains('WorkbenchBackAction'), isTrue,
            reason: '$path must reuse WorkbenchBackAction for its return path');
        expect(source.contains('returnToDashboard'), isTrue,
            reason: '$path must still surface the return-to-lobby label');
      }
    });

    test('preset scenes no longer builds the legacy AppBar chrome', () {
      final source = File(_workbenchPages[1]).readAsStringSync();
      expect(source.contains('appBar:'), isFalse);
      expect(source.contains('AppBar('), isFalse);
      expect(source.contains('leadingWidth'), isFalse);
    });

    test('page return navigation is never a filled / tonal CTA', () {
      for (final path in _workbenchPages) {
        final lines = File(path).readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i].contains('returnToDashboard')) continue;
          final window =
              lines.sublist(max(0, i - 4), min(lines.length, i + 5)).join('\n');
          expect(window.contains('FilledButton'), isFalse,
              reason:
                  'the return control in $path must not be a filled button');
        }
      }
    });
  });
}
