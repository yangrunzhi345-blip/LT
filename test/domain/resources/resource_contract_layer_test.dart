import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../architecture/source_imports.dart';

/// Phase 0 acceptance is a *structural* property: the contract layer must be
/// plain Dart, and the frozen capacity numbers must live in exactly one file.
/// These guards fail the build if a later change erodes either property.
const String _contractDirectory = 'lib/domain/resources';

/// URIs the contract layer may never import.
const List<String> _forbiddenUriPrefixes = [
  'dart:io',
  'dart:ui',
  'package:flutter',
  'package:sqflite',
  'package:http',
  'package:path',
];

/// Outer layers the contract layer may never depend on.
const List<String> _forbiddenTargetPrefixes = [
  'lib/application/',
  'lib/controllers/',
  'lib/core/',
  'lib/data/',
  'lib/engines/',
  'lib/features/',
  'lib/managers/',
  'lib/models/',
  'lib/providers/',
  'lib/screens/',
  'lib/services/',
  'lib/utils/',
  'lib/widgets/',
];

/// The four frozen capacity numbers, which must only appear in
/// `resource_limits.dart`.
final RegExp _capacityLiterals = RegExp(r'\b(50000|60000|20000|24000)\b');

/// The only sanctioned JSON codec call in the contract layer: decoding a SINGLE
/// Structured Part's body (`structuredObjectV1`) to check its required fields.
///
/// ADR-0001 §5 forbids serializing a WHOLE resource tree as one giant JSON
/// column and forbids physical nesting — it does not forbid validating one
/// limited node. So `jsonDecode` is allowed in exactly this one file, while:
///   * `jsonEncode` / `toJson` (serialization) stay forbidden EVERYWHERE, that
///     file included;
///   * `jsonDecode` stays forbidden in every OTHER contract file.
/// The contract layer therefore never gains general-purpose JSON codec access.
const Map<String, Set<String>> _sanctionedJsonCodecUsage = {
  'lib/domain/resources/content_requirements.dart': {'jsonDecode'},
};

/// JSON codec identifiers that would let the contract layer serialize or
/// deserialize a resource tree.
const List<String> _jsonCodecTokens = ['jsonEncode', 'jsonDecode', 'toJson'];

/// Reports every non-sanctioned JSON codec usage in a `path -> source` map.
///
/// Pure, so the guard itself can be tested negatively (proving a newly added
/// codec call would still fail the build) without editing real sources.
List<String> _jsonSerializationViolations(Map<String, String> sources) {
  final offenders = <String>[];
  for (final entry in sources.entries) {
    final allowed = _sanctionedJsonCodecUsage[entry.key] ?? const <String>{};
    for (final token in _jsonCodecTokens) {
      if (entry.value.contains(token) && !allowed.contains(token)) {
        offenders.add('${entry.key} uses $token');
      }
    }
  }
  offenders.sort();
  return offenders;
}

void main() {
  group('Contract layer purity', () {
    final files = dartFilesUnder(_contractDirectory);

    test('the contract layer exists and is scanned', () {
      expect(files, isNotEmpty);
      expect(
        files.any((path) => path.endsWith('resource_limits.dart')),
        isTrue,
      );
    });

    test('imports no Flutter, SQLite, HTTP or outer application layer', () {
      final violations = <String>[];
      for (final import in collectImports(_contractDirectory)) {
        if (_forbiddenUriPrefixes.any(import.uri.startsWith)) {
          violations.add(import.edge);
          continue;
        }
        final target = import.target;
        if (target != null && _forbiddenTargetPrefixes.any(target.startsWith)) {
          violations.add(import.edge);
        }
      }

      violations.sort();
      expect(
        violations,
        isEmpty,
        reason: 'The resource contract layer must stay pure Dart:\n'
            '${violations.join('\n')}',
      );
    });

    test('never serializes a whole resource as JSON', () {
      final sources = <String, String>{
        for (final path in files) path: File(path).readAsStringSync(),
      };
      final offenders = _jsonSerializationViolations(sources);

      expect(
        offenders,
        isEmpty,
        reason: 'Whole-resource JSON serialization is forbidden in the '
            'contract layer (ADR-0001):\n${offenders.join('\n')}',
      );
    });

    test('confines the sanctioned decode to the structured Part body', () {
      final source = File(
        '$_contractDirectory/content_requirements.dart',
      ).readAsStringSync();
      // The one allowed codec call decodes the Part body for the structured
      // profile; serialization and any other shape stay banned even here.
      // Matched by intent (a jsonDecode call + the structured profile) rather
      // than the local variable name, so a behaviour-preserving rename does
      // not spuriously fail the guard.
      expect(source.contains('jsonEncode'), isFalse);
      expect(source.contains('toJson'), isFalse);
      expect(RegExp(r'\bjsonDecode\s*\(').hasMatch(source), isTrue);
      expect(source.contains('structuredObjectV1'), isTrue);
    });

    group('the JSON guard still fails closed on new offenders', () {
      const sanctioned = 'lib/domain/resources/content_requirements.dart';

      test('flags jsonDecode added to any other contract file', () {
        expect(
          _jsonSerializationViolations({
            'lib/domain/resources/new_node.dart': 'final v = jsonDecode(raw);',
          }),
          ['lib/domain/resources/new_node.dart uses jsonDecode'],
        );
      });

      test('flags jsonEncode even inside the sanctioned file', () {
        expect(
          _jsonSerializationViolations({
            sanctioned: 'final v = jsonEncode(tree);',
          }),
          ['$sanctioned uses jsonEncode'],
        );
      });

      test('flags toJson even inside the sanctioned file', () {
        expect(
          _jsonSerializationViolations({
            sanctioned: 'Map<String, Object?> toJson() => {};',
          }),
          ['$sanctioned uses toJson'],
        );
      });

      test('flags a whole-resource snapshot anywhere in the layer', () {
        expect(
          _jsonSerializationViolations({
            'lib/domain/resources/resource_contracts.dart':
                'String toJson() => jsonEncode(this);',
          }),
          [
            'lib/domain/resources/resource_contracts.dart uses jsonEncode',
            'lib/domain/resources/resource_contracts.dart uses toJson',
          ],
        );
      });

      test('allows only the sanctioned single-Part jsonDecode', () {
        expect(
          _jsonSerializationViolations({
            sanctioned: 'final decoded = jsonDecode(body);',
          }),
          isEmpty,
        );
      });
    });

    test('keeps the four capacity numbers inside resource_limits.dart', () {
      final offenders = <String>[];
      for (final path in files) {
        if (path.endsWith('resource_limits.dart')) continue;
        if (_capacityLiterals.hasMatch(File(path).readAsStringSync())) {
          offenders.add(path);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Capacity numbers must come from ResourceLimits instead of '
            'being copied into another contract file:\n${offenders.join('\n')}',
      );
    });

    test('makes ResourcePart the only tree node that owns long body text', () {
      final source = File(
        '$_contractDirectory/resource_contracts.dart',
      ).readAsStringSync();
      final contentField = RegExp(r'final String content\s*;');

      final partStart = source.indexOf('final class ResourcePart');
      final treeStart = source.indexOf('final class ResourceTree');
      expect(partStart, greaterThan(0));
      expect(treeStart, greaterThan(partStart));

      expect(
        contentField.hasMatch(source.substring(0, partStart)),
        isFalse,
        reason: 'Resource and ResourceSection must not carry body text.',
      );
      expect(
        contentField.allMatches(source.substring(partStart, treeStart)).length,
        1,
        reason: 'ResourcePart must own exactly one content field.',
      );
    });
  });
}
