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

/// Temporary, file-exact exceptions. Each entry documents why the edge still
/// exists and where it should move.
class _AllowlistedEdge {
  final String file;
  final String forbiddenTarget;
  final String reason;
  final String todo;

  const _AllowlistedEdge({
    required this.file,
    required this.forbiddenTarget,
    required this.reason,
    required this.todo,
  });

  String get key => '$file -> $forbiddenTarget';
}

const List<_AllowlistedEdge> _allowlist = [
  _AllowlistedEdge(
    file:
        'lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart',
    forbiddenTarget: 'lib/services/worldview_snapshot_service.dart',
    reason: 'Wizard state method builds the worldview snapshot inline.',
    todo: 'TODO(P2): route WorldviewSnapshotService.snapshot through a '
        'controller/provider and drop this import.',
  ),
  _AllowlistedEdge(
    file:
        'lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart',
    forbiddenTarget: 'lib/services/character_card_storage_adapter.dart',
    reason: 'Wizard state method canonicalizes generated cards inline.',
    todo: 'TODO(P2): route CharacterCardStorageAdapter through a '
        'controller/provider and drop this import.',
  ),
  _AllowlistedEdge(
    file:
        'lib/features/settings/presentation/widgets/provider_config_section.dart',
    forbiddenTarget: 'lib/services/api_error.dart',
    reason: 'Connection test maps the raw ApiError inside the widget state.',
    todo: 'TODO(P2): surface a mapped error type from the settings controller '
        'instead of importing services/api_error.dart.',
  ),
  _AllowlistedEdge(
    file:
        'lib/features/adventure/presentation/templates/screens/preset_scenes_screen.dart',
    forbiddenTarget: 'lib/data/preset_adventures.dart',
    reason: 'Preset scene screen passes PresetAdventureData through state.',
    todo: 'TODO(P2): expose preset data through a repository/provider so '
        'presentation no longer imports data/preset_adventures.dart.',
  ),
];

void main() {
  group('Presentation boundary', () {
    test('imports no services/engines/managers/data except the allowlist', () {
      final violations = <String>[];
      for (final import in collectImports('lib')) {
        if (!_isPresentation(import.importer)) continue;
        final target = import.target;
        if (target == null) continue;
        if (_forbiddenPrefixes.any(target.startsWith)) {
          violations.add(import.edge);
        }
      }

      final allowed = _allowlist.map((entry) => entry.key).toSet();
      final unexpected =
          violations.where((edge) => !allowed.contains(edge)).toList()..sort();

      expect(
        unexpected,
        isEmpty,
        reason: 'Presentation must not import infrastructure layers. '
            'Route these through application/providers instead:\n'
            '${unexpected.join('\n')}',
      );
    });

    test('allowlist has no stale entries', () {
      final violations = <String>{};
      for (final import in collectImports('lib')) {
        if (!_isPresentation(import.importer)) continue;
        final target = import.target;
        if (target == null) continue;
        if (_forbiddenPrefixes.any(target.startsWith)) {
          violations.add(import.edge);
        }
      }

      final stale = _allowlist
          .map((entry) => entry.key)
          .where((key) => !violations.contains(key))
          .toList();

      expect(
        stale,
        isEmpty,
        reason: 'These allowlist entries no longer correspond to a real '
            'violation; remove them:\n${stale.join('\n')}',
      );
    });

    test('allowlist entries stay file-exact and never allow a whole layer', () {
      for (final entry in _allowlist) {
        expect(
          entry.forbiddenTarget.endsWith('/'),
          isFalse,
          reason: 'Allowlist entry "${entry.key}" must name an exact file, '
              'not a directory prefix.',
        );
        expect(entry.todo, startsWith('TODO'),
            reason: 'Allowlist entry "${entry.key}" needs a TODO.');
        expect(entry.reason, isNotEmpty);
      }
    });
  });
}
