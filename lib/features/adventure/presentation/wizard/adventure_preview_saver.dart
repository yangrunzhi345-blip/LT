import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../providers/riverpod_providers.dart';

/// Outcome of persisting an assembly preview.
enum AdventurePreviewSaveOutcome { saved, duplicate }

/// Single entry point for "save the current assembly as a recoverable preview
/// without starting the adventure".
///
/// Delegates to [AdventureTemplateController.saveAdventurePreview] so the
/// preview marker, the ContentHasher dedupe and the persistence path stay
/// single-sourced across the legacy wizard, [AssemblyCreatePage] and
/// [AssemblyPreviewPage]. It deliberately shows no UI feedback, never touches
/// the readiness gate and never starts a session — callers own presentation.
class AdventurePreviewSaver {
  const AdventurePreviewSaver._();

  static Future<AdventurePreviewSaveOutcome> save({
    required WidgetRef ref,
    required AdventureConfig config,
    required AppLocalizations l10n,
    required String worldviewName,
    required String worldviewDesc,
    required String idPrefix,
  }) async {
    final controller = ref.read(adventureTemplateControllerProvider);
    final saved = await controller.saveAdventurePreview(
      id: '${idPrefix}_${DateTime.now().millisecondsSinceEpoch}',
      name: l10n.adventurePreviewName(worldviewName),
      worldviewName: worldviewName,
      worldviewDesc: worldviewDesc.isNotEmpty ? worldviewDesc : worldviewName,
      config: config,
    );
    return saved
        ? AdventurePreviewSaveOutcome.saved
        : AdventurePreviewSaveOutcome.duplicate;
  }
}
