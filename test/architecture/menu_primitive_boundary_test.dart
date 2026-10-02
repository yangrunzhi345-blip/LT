import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_imports.dart';

/// Every dropdown / popup surface must be rendered by the single menu kernel.
///
/// `lib/core/widgets/app_menu.dart` is the only file allowed to touch a raw
/// Flutter menu primitive. Feature (`lib/features/**`) and screen
/// (`lib/screens/**`) code — and the facade widgets that sit on top of the
/// kernel — must describe semantics only and delegate the rendering.
const Set<String> _kernelAllowlist = <String>{
  'lib/core/widgets/app_menu.dart',
};

/// Maps a friendly name to the matcher used to detect the raw primitive.
///
/// `\bMenuAnchor\b` deliberately does not match the app-owned `AppMenuAnchor`
/// wrapper, and `showMenu` requires a generic/call marker so prose and
/// similarly named helpers are not caught.
final Map<String, RegExp> _forbiddenPrimitives = <String, RegExp>{
  'PopupMenuButton': RegExp(r'\bPopupMenuButton\b'),
  'PopupMenuItem': RegExp(r'\bPopupMenuItem\b'),
  'DropdownButton': RegExp(r'\bDropdownButton\b'),
  'DropdownButtonFormField': RegExp(r'\bDropdownButtonFormField\b'),
  'DropdownMenu': RegExp(r'\bDropdownMenu\b'),
  'MenuAnchor': RegExp(r'\bMenuAnchor\b'),
  'showMenu': RegExp(r'\bshowMenu\s*[<(]'),
  'OverlayEntry': RegExp(r'\bOverlayEntry\b'),
};

void main() {
  group('Menu primitive boundary', () {
    test('only the shared menu kernel builds raw menu primitives', () {
      final violations = <String>[];
      for (final path in dartFilesUnder('lib')) {
        if (_kernelAllowlist.contains(path)) continue;
        final source = File(path).readAsStringSync();
        for (final entry in _forbiddenPrimitives.entries) {
          if (entry.value.hasMatch(source)) {
            violations.add('$path -> ${entry.key}');
          }
        }
      }
      violations.sort();

      expect(
        violations,
        isEmpty,
        reason: 'Dropdown / popup primitives must go through the shared menu '
            'kernel (${_kernelAllowlist.join(', ')}). Route these through '
            'AppSelect / AppActionMenu / AppMultiSelectDropdown instead:\n'
            '${violations.join('\n')}',
      );
    });

    test('feature and screen layers are free of raw menu primitives', () {
      final violations = <String>[];
      for (final path in dartFilesUnder('lib')) {
        final isFeatureOrScreen =
            path.startsWith('lib/features/') || path.startsWith('lib/screens/');
        if (!isFeatureOrScreen) continue;
        final source = File(path).readAsStringSync();
        for (final entry in _forbiddenPrimitives.entries) {
          if (entry.value.hasMatch(source)) {
            violations.add('$path -> ${entry.key}');
          }
        }
      }
      violations.sort();

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('the kernel owns the anchored menu primitive', () {
      final source = File('lib/core/widgets/app_menu.dart').readAsStringSync();
      expect(
        _forbiddenPrimitives['MenuAnchor']!.hasMatch(source),
        isTrue,
        reason: 'The shared menu kernel must own the raw anchored menu.',
      );
    });
  });
}
