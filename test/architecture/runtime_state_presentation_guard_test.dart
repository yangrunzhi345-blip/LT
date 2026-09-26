import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('state presentation does not render runtime protocol fields directly',
      () {
    final directory = Directory(
      'lib/features/adventure/presentation/state',
    );
    final violations = <String>[];
    final forbidden = RegExp(
      r'Text\((?!RuntimeStatePresentation\.)[^\n]*(?:entityId|\.path|lifecycleStatus|causeType|entityType\.name|importance\.name)',
    );
    for (final file in directory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (forbidden.hasMatch(lines[index])) {
          violations.add('${file.path}:${index + 1}: ${lines[index].trim()}');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
