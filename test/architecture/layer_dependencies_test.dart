import 'package:flutter_test/flutter_test.dart';

import 'source_imports.dart';

/// `lib/managers/**` is an outer orchestration layer and must not depend on
/// `lib/engines/**` (the engines are driven by providers). The former
/// `managers/chat_dependencies.dart` edge was removed in this change; this
/// gate freezes that direction.
void main() {
  group('Layer dependencies', () {
    test('lib/managers does not import lib/engines', () {
      final violations = <String>[];
      for (final import in collectImports('lib')) {
        if (!import.importer.startsWith('lib/managers/')) continue;
        final target = import.target;
        if (target != null && target.startsWith('lib/engines/')) {
          violations.add(import.edge);
        }
      }

      violations.sort();
      expect(
        violations,
        isEmpty,
        reason:
            'Managers must not depend on engines:\n${violations.join('\n')}',
      );
    });
  });
}
