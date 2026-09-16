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
final RegExp _capacityLiterals = RegExp(r'\b(50000|60000|5000|6000)\b');

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
      final offenders = <String>[];
      for (final path in files) {
        final source = File(path).readAsStringSync();
        for (final banned in const ['jsonEncode', 'jsonDecode', 'toJson']) {
          if (source.contains(banned)) {
            offenders.add('$path uses $banned');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Whole-resource JSON serialization is forbidden in the '
            'contract layer (ADR-0001):\n${offenders.join('\n')}',
      );
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
