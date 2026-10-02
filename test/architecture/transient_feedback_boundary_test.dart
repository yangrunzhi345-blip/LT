import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Transient user feedback has a single authority: [AppFeedback], rendered as a
/// centred overlay. Feature / screen / widget code must never push its own
/// bottom SnackBar — that is what produced inconsistent, bottom-anchored
/// messages. This guard keeps the migration from regressing.
///
/// `SnackBarThemeData` (theme contract) is intentionally allowed; only the
/// runtime primitives are forbidden.
void main() {
  test('no raw SnackBar / ScaffoldMessenger outside the feedback authority',
      () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = entity
          .readAsStringSync()
          .split('\n')
          // Ignore line comments so prose about SnackBars is not a false hit.
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      if (code.contains('SnackBar(') ||
          code.contains('showSnackBar') ||
          code.contains('ScaffoldMessenger')) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Transient feedback must go through AppFeedback; found raw '
          'SnackBar usage in: $offenders',
    );
  });
}
