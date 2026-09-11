import 'package:flutter_test/flutter_test.dart';

import 'source_imports.dart';

/// Domain models must not depend on Flutter UI, theme, widgets or feature
/// presentation. `package:flutter/foundation.dart` is intentionally allowed
/// for now (`ChangeNotifier` / `VoidCallback` / `@visibleForTesting` are used
/// by engines, managers and providers); a pure-Dart domain is a P5 goal.
const List<String> _forbiddenUriPrefixes = [
  'dart:ui',
  'package:flutter/material.dart',
  'package:flutter/widgets.dart',
];

const List<String> _forbiddenTargetPrefixes = [
  'lib/core/theme/',
  'lib/widgets/',
  'lib/screens/',
];

bool _isModel(String path) => path.startsWith('lib/models/');

void main() {
  group('Models boundary', () {
    test('models import no Flutter UI, theme, widgets or presentation code',
        () {
      final violations = <String>[];
      for (final import in collectImports('lib')) {
        if (!_isModel(import.importer)) continue;

        final uri = import.uri;
        final target = import.target;
        final forbiddenUri =
            _forbiddenUriPrefixes.any((prefix) => uri.startsWith(prefix));
        final forbiddenTarget = target != null &&
            (_forbiddenTargetPrefixes.any(target.startsWith) ||
                target.contains('/presentation/'));

        if (forbiddenUri || forbiddenTarget) {
          violations.add(import.edge);
        }
      }

      violations.sort();
      expect(
        violations,
        isEmpty,
        reason: 'Domain models must stay free of presentation concerns. '
            'Move UI types (Color/IconData/etc.) into a core/theme or '
            'feature extension instead:\n${violations.join('\n')}',
      );
    });
  });
}
