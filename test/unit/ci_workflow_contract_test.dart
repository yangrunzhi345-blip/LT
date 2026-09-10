import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the CI-01 contract: the repository must keep a regression gate that
/// runs format/analyze/test on the way into `main`, and the release workflow
/// must repeat those checks plus the tag/version and ARM64/SHA invariants before
/// publishing. Required branch-protection status checks are a GitHub repository
/// setting and are documented in `quality-gate.yml`, not enforceable here.
void main() {
  const formatCommand = 'dart format --output=none --set-exit-if-changed .';
  const analyzeCommand = 'flutter analyze';
  const testCommand = 'flutter test --reporter compact';

  test('quality gate runs format, analyze and tests on main and PRs', () {
    final file = File('.github/workflows/quality-gate.yml');
    expect(file.existsSync(), isTrue, reason: 'quality-gate.yml must exist');

    final content = file.readAsStringSync();
    for (final needle in [
      'pull_request',
      'push:',
      'flutter pub get',
      formatCommand,
      analyzeCommand,
      testCommand,
    ]) {
      expect(content, contains(needle),
          reason: 'quality-gate.yml missing: $needle');
    }
  });

  test('release repeats the gate and keeps tag/version and ARM64/SHA checks',
      () {
    final file = File('.github/workflows/release-arm64.yml');
    expect(file.existsSync(), isTrue, reason: 'release-arm64.yml must exist');

    final content = file.readAsStringSync();
    for (final needle in [
      formatCommand,
      analyzeCommand,
      testCommand,
      'Verify release tag matches pubspec version',
      'android-arm64',
      'sha256sum',
      'gh release create',
    ]) {
      expect(content, contains(needle),
          reason: 'release-arm64.yml missing: $needle');
    }
  });
}
