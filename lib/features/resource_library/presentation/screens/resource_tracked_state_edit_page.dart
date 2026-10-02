import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/resource_library/edit_drafts.dart';
import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_loading_view.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../core/widgets/tracked_state_definition_editor_section.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../models/resource_library_mode.dart';
import '../../../../models/tracked_state_definition.dart';
import '../../../../providers/riverpod_providers.dart';

/// Focused editor for one owner resource's monitoring **definitions**.
///
/// One page for character, NPC and worldview: the aggregate「检测项目」surface
/// opens this instead of three different editors, so editing a definition has
/// the same interaction on every owner type. It changes only
/// `trackedStateDefinitions` and saves through the owner's existing authority,
/// which preserves every other field of the resource.
final class ResourceTrackedStateEditPage extends ConsumerStatefulWidget {
  const ResourceTrackedStateEditPage({
    super.key,
    required this.ownerType,
    required this.resourceId,
    this.mode = ResourceLibraryMode.adventure,
  });

  final ResourceType ownerType;
  final String resourceId;
  final ResourceLibraryMode mode;

  @override
  ConsumerState<ResourceTrackedStateEditPage> createState() =>
      _ResourceTrackedStateEditPageState();
}

final class _ResourceTrackedStateEditPageState
    extends ConsumerState<ResourceTrackedStateEditPage> {
  Map<String, dynamic>? _row;
  List<TrackedStateDefinition> _definitions = const [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    final runtime = ref.read(trackedStateLibraryRuntimeProvider);
    final row = await runtime.loadOwnerRow(
      type: widget.ownerType,
      resourceId: widget.resourceId,
      mode: widget.mode,
    );
    if (!mounted) return;
    setState(() {
      _row = row;
      _definitions = row == null ? const [] : _definitionsOf(row);
      _loading = false;
    });
  }

  List<TrackedStateDefinition> _definitionsOf(Map<String, dynamic> row) =>
      switch (widget.ownerType) {
        ResourceType.character =>
          CharacterCardEditDraft.fromExisting(row).trackedStateDefinitions,
        ResourceType.npc =>
          NpcEditDraft.fromExisting(row).trackedStateDefinitions,
        ResourceType.worldview =>
          WorldviewEditDraft.fromExisting(row).trackedStateDefinitions,
      };

  /// Persists only the definitions, through the owner's existing save
  /// authority, so the rest of the resource is untouched.
  Future<bool> _persist(List<TrackedStateDefinition> definitions) async {
    final row = _row;
    if (row == null) return false;
    final crud = ref.read(resourceCrudControllerProvider);
    final result = switch (widget.ownerType) {
      ResourceType.character => await crud.saveCharacterCardDraft(
          CharacterCardEditDraft.fromExisting(row)
            ..trackedStateDefinitions = definitions,
          mode: widget.mode,
        ),
      ResourceType.npc => await crud.saveNpcDraft(
          NpcEditDraft.fromExisting(row)..trackedStateDefinitions = definitions,
          mode: widget.mode,
        ),
      ResourceType.worldview => await crud.saveWorldviewDraft(
          WorldviewEditDraft.fromExisting(row)
            ..trackedStateDefinitions = definitions,
          mode: widget.mode,
        ),
    };
    return result.success;
  }

  Future<void> _save(AppLocalizations l10n) async {
    setState(() => _saving = true);
    final ok = await _persist(_definitions);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(true);
      return;
    }
    AppFeedback.error(context, l10n.characterCardSaveFailed(''));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    if (_loading) {
      return AppPageScaffold(
        title: l10n.resourceTrackedStateTab,
        body: const AppLoadingView(),
      );
    }
    final row = _row;
    if (row == null) {
      return AppPageScaffold(
        title: l10n.resourceTrackedStateTab,
        body: AppEmptyState(
          icon: 'resources',
          title: l10n.resourceNoMatches,
        ),
      );
    }

    final theme = Theme.of(context);
    final ownerName = (row['name']?.toString().trim() ?? '').isEmpty
        ? l10n.resourceUnnamed
        : row['name'].toString().trim();
    final typeLabel = switch (widget.ownerType) {
      ResourceType.character => l10n.trackedStateEntityTypeCharacter,
      ResourceType.npc => l10n.trackedStateEntityTypeNpc,
      ResourceType.worldview => l10n.resourceTypeWorldview,
    };

    return AppPageScaffold(
      title: l10n.resourceTrackedStateTab,
      maxWidth: 760,
      bottomBar: _buildSaveBar(context, l10n),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: [
          Text(
            ownerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(
            typeLabel,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          TrackedStateDefinitionEditorSection(
            key: ValueKey(
                'tracked-state-editor-${widget.ownerType.name}-${widget.resourceId}'),
            initialItems: _definitions,
            onChanged: (items) => _definitions = items,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton(
            key: const Key('tracked-state-edit-save'),
            onPressed: _saving ? null : () => _save(l10n),
            child: Text(l10n.saveAction),
          ),
        ],
      ),
    );
  }
}
