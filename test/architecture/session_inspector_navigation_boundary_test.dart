import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sources that own the Session Inspector presentation.
const List<String> _inspectorSources = <String>[
  'lib/features/adventure/presentation/session/screens/adventure_session_screen.dart',
  'lib/features/adventure/presentation/session/screens/session_inspector_page.dart',
  'lib/features/adventure/presentation/session/widgets/session_inspector.dart',
];

/// Guard: the Session Inspector is a real page, never a transient surface.
///
/// Bottom sheets and dialogs remain legitimate elsewhere in the app; this guard
/// is scoped to the Inspector's own sources so it can never quietly regress back
/// to a modal, overlay or inline side pane.
void main() {
  group('Session Inspector navigation boundary', () {
    test('never presents the Inspector as a modal, overlay or inline pane', () {
      const banned = <String>[
        'showModalBottomSheet',
        'showDialog',
        'showGeneralDialog',
        'OverlayEntry',
        'OverlayPortal',
      ];
      for (final path in _inspectorSources) {
        final source = File(path).readAsStringSync();
        for (final token in banned) {
          expect(source.contains(token), isFalse,
              reason: '$path must not use $token for the Session Inspector');
        }
      }
    });

    test('the session screen pushes the standalone Inspector page', () {
      final source = File(_inspectorSources[0]).readAsStringSync();
      expect(source.contains('SessionInspectorPage'), isTrue,
          reason: 'the session screen must open the Inspector page');
      expect(source.contains('MaterialPageRoute'), isTrue,
          reason: 'the Inspector must be a pushed route');
      expect(source.contains('_openInspectorPage'), isTrue);
      // Dead modal/inline plumbing must not linger.
      expect(source.contains('_inspectorVisible'), isFalse);
      expect(source.contains('_hasInlineInspector'), isFalse);
      expect(source.contains('FractionallySizedBox'), isFalse);
      expect(source.contains('StatefulBuilder'), isFalse);
    });

    test('the Inspector content has no popup-specific close contract', () {
      final source = File(_inspectorSources[2]).readAsStringSync();
      expect(source.contains('onClose'), isFalse,
          reason: 'page chrome owns navigation; content must not close itself');
      expect(source.contains('workbenchInspector'), isFalse,
          reason: 'the page AppBar owns the title');
    });
  });
}
