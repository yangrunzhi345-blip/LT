import 'package:flutter_test/flutter_test.dart';

import 'source_imports.dart';

/// Presentation must stay a consumer of application/provider layers and must
/// not reach into infrastructure directly.
///
/// `package:flutter/foundation.dart` is intentionally NOT part of this rule;
/// only the feature presentation layer is scanned, and `lib/screens/**` is the
/// separate legacy layer that is out of scope for this gate.
const List<String> _forbiddenPrefixes = [
  'lib/services/',
  'lib/engines/',
  'lib/managers/',
  'lib/data/',
];

bool _isPresentation(String path) =>
    path.startsWith('lib/features/') && path.contains('/presentation/');

void main() {
  group('Presentation boundary', () {
    test('imports no services, engines, managers or data', () {
      final violations = <String>[];
      for (final import in collectImports('lib')) {
        if (!_isPresentation(import.importer)) continue;
        final target = import.target;
        if (target == null) continue;
        if (_forbiddenPrefixes.any(target.startsWith)) {
          violations.add(import.edge);
        }
      }

      violations.sort();
      expect(
        violations,
        isEmpty,
        reason: 'Presentation must not import infrastructure layers. '
            'Route these through application/providers instead:\n'
            '${violations.join('\n')}',
      );
    });
  });
}
