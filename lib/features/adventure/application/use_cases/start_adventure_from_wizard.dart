import '../../../../application/adventure/adventure_readiness_gate.dart';
import '../../../../controllers/adventure_setup_controller.dart';
import '../../../../controllers/resource_crud_controller.dart';
import '../../../../domain/errors/app_error.dart';
import '../../../../domain/setting_cards/setting_card_repository.dart';
import '../../../../models/adventure_config.dart';
import '../../../../models/resource_library_mode.dart';

/// Wizard draft of the worldview currently being edited.
///
/// Pure data: the screen extracts it from its controllers/state so the start
/// orchestration never has to read widgets.
final class WizardWorldviewDraft {
  const WizardWorldviewDraft({
    required this.id,
    required this.name,
    required this.description,
    required this.detailJson,
    required this.saveToLibrary,
  });

  final String id;
  final String name;
  final String description;
  final String detailJson;
  final bool saveToLibrary;
}

/// Wizard draft of one roster character, already serialized for persistence.
final class WizardCharacterDraft {
  const WizardCharacterDraft({
    required this.id,
    required this.name,
    required this.jsonData,
    required this.matchingWorldviewId,
  });

  final String id;
  final String name;
  final String jsonData;

  /// Empty when the character is not bound to a specific worldview; the use
  /// case then falls back to the active wizard worldview.
  final String matchingWorldviewId;
}

/// Everything the start boundary needs to persist before composing a config.
final class WizardStartDraft {
  const WizardStartDraft({
    required this.worldview,
    required this.characters,
    required this.saveCharacters,
  });

  final WizardWorldviewDraft worldview;
  final List<WizardCharacterDraft> characters;
  final bool saveCharacters;
}

/// Outcome of [StartAdventureFromWizardUseCase.prepare].
sealed class WizardStartOutcome {
  const WizardStartOutcome();
}

/// Every referenced asset is ready; [config] may be started as-is.
final class WizardStartReady extends WizardStartOutcome {
  const WizardStartReady(this.config);

  final AdventureConfig config;
}

/// At least one asset can never be used as configured (preparing, failed or
/// without any ready revision). Starting is not allowed.
final class WizardStartBlocked extends WizardStartOutcome {
  const WizardStartBlocked(this.issues);

  final List<AdventureAssetReadiness> issues;
}

/// Only stale assets with a previously ready revision block the start. The
/// user must explicitly choose whether to reuse those revisions.
final class WizardStartNeedsStaleConfirmation extends WizardStartOutcome {
  const WizardStartNeedsStaleConfirmation({
    required this.config,
    required this.stale,
  });

  final AdventureConfig config;
  final List<AdventureAssetReadiness> stale;
}

/// Application use case behind the Adventure Wizard start button.
///
/// It owns the business part of starting an adventure: persisting the edited
/// worldview and roster into the resource library, rebuilding the worldview
/// snapshot, resolving the readiness gate and returning a typed outcome. The
/// screen keeps input collection, localizations, dialogs and navigation.
class StartAdventureFromWizardUseCase {
  const StartAdventureFromWizardUseCase({
    required ResourceCrudController crud,
    required AdventureSetupController setup,
    required IAdventureReadinessGate gate,
    required SettingCardRepository cards,
    this.sourceLabel = '冒险向导',
  })  : _crud = crud,
        _setup = setup,
        _gate = gate,
        _cards = cards;

  final ResourceCrudController _crud;
  final AdventureSetupController _setup;
  final IAdventureReadinessGate _gate;
  final SettingCardRepository _cards;
  final String sourceLabel;

  /// Persists the draft, composes the config through [composeConfig] and runs
  /// the Phase 10 readiness gate.
  ///
  /// [composeConfig] stays a caller-provided port because the config is built
  /// from wizard widgets (controllers, roster items, opening text); the use
  /// case only decides *when* it is composed, with the refreshed snapshot.
  ///
  /// Persistence failures propagate as the original domain error so the screen
  /// can localize a single message for the whole boundary.
  Future<WizardStartOutcome> prepare({
    required WizardStartDraft draft,
    required AdventureConfig Function(Map<String, dynamic>? worldviewSnapshot)
        composeConfig,
  }) async {
    final now = DateTime.now().toIso8601String();
    final worldview = draft.worldview;

    // A setting card is already the durable authority. Writing it through the
    // legacy preset path would create a res_legacy_* mirror next to the card
    // and duplicate every generated asset in the library.
    final existingWorldview = await _cards.findById(worldview.id);
    if (existingWorldview != null) {
      await _cards.save(existingWorldview.copyWith(
        name: worldview.name,
        summary: worldview.description,
        updatedAt: now,
      ));
    } else if (worldview.saveToLibrary) {
      final result = await _crud.saveWorldviewPreset(
        id: worldview.id,
        name: worldview.name,
        description: worldview.description,
        entriesJson: '[]',
        now: now,
        detailJson: worldview.detailJson,
        source: sourceLabel,
        mode: ResourceLibraryMode.adventure,
        validate: false,
      );
      if (!result.success) {
        throw result.error ?? const AppDomainError(code: AppErrorCode.unknown);
      }
    }

    // Reload so the snapshot below sees the just-persisted worldview row.
    await _setup.loadInitialData();
    final snapshot = _setup.buildWorldviewSnapshot(
          id: worldview.id,
          worldview: worldview.name,
        ) ??
        _setup.buildWorldviewSnapshotFromDetails(
          id: worldview.id,
          name: worldview.name,
          description: worldview.description,
          detailJson: worldview.detailJson,
        );

    if (draft.saveCharacters) {
      for (final character in draft.characters) {
        // Card-backed roster rows are already persisted; the legacy write only
        // exists for characters that have never left the old tables.
        if (await _cards.findById(character.id) != null) continue;
        final result = await _crud.saveCharacterCard(
          id: character.id,
          name: character.name,
          jsonData: character.jsonData,
          source: sourceLabel,
          now: now,
          matchingWorldviewId: character.matchingWorldviewId.isNotEmpty
              ? character.matchingWorldviewId
              : worldview.id,
          mode: ResourceLibraryMode.adventure,
        );
        if (!result.success) {
          throw result.error ??
              const AppDomainError(code: AppErrorCode.unknown);
        }
      }
    }

    final config = composeConfig(snapshot);
    return _classify(config);
  }

  /// Applies the user's explicit "reuse the previous ready revision" choice.
  AdventureConfig acceptStale(WizardStartNeedsStaleConfirmation outcome) {
    return outcome.config.copyWith(
      resourceBindings: [
        ...outcome.config.resourceBindings,
        ...outcome.stale.map(
          (readiness) => AdventureResourceBinding(
            resourceId: readiness.assetId,
            revisionId: readiness.assemblyRevisionId,
            contentHash: readiness.assemblyContentHash,
            staleAllowed: true,
          ),
        ),
      ],
    );
  }

  Future<WizardStartOutcome> _classify(AdventureConfig config) async {
    final statuses = await _gate.resolveConfig(config);
    final blocked = statuses.values
        .where((readiness) => readiness.status.blocksStart)
        .toList(growable: false);
    if (blocked.isEmpty) return WizardStartReady(config);

    final hardBlocked = blocked
        .where((readiness) =>
            readiness.status != AdventureAssetGateStatus.staleWithPreviousReady)
        .toList(growable: false);
    if (hardBlocked.isNotEmpty) return WizardStartBlocked(hardBlocked);

    return WizardStartNeedsStaleConfirmation(config: config, stale: blocked);
  }
}
