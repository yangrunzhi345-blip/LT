import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../core/widgets/form_sub_page_scaffold.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_zh.dart';
import '../../models/resource_library_mode.dart';
import '../../models/scene_batch_candidate.dart';
import '../../providers/riverpod_providers.dart';
import '../../core/utils/worldview_character_scope_policy.dart';
import '../../application/resources/resource_creation_contracts.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/resource_limits.dart';
import '../../features/resource_studio/presentation/pages/resource_studio_page.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

enum SceneBatchImportKind { character, npc }

enum SceneImportDetailMode { concise, detailed }

extension SceneImportDetailModeText on SceneImportDetailMode {
  String localizedLabel(AppLocalizations l10n) =>
      this == SceneImportDetailMode.concise
          ? l10n.conciseMode
          : l10n.detailedMode;

  String get label => this == SceneImportDetailMode.concise ? '简洁模式' : '详细模式';

  String get instruction => this == SceneImportDetailMode.concise
      ? '使用简洁模式：保留身份、性格、外貌、核心经历和必要关系，避免扩写。'
      : '使用详细模式：在原文事实范围内完整整理身份、性格、外貌、经历、动机、信息与人物关系。';
}

Future<SceneImportDetailMode?> showSceneImportDetailModePicker(
    BuildContext context) {
  final l10n = _l10n(context);
  return showDialog<SceneImportDetailMode>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.selectImportModeTitle),
      content: Text(l10n.selectImportModeDesc),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, SceneImportDetailMode.concise),
          child: Text(l10n.conciseMode),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(dialogContext, SceneImportDetailMode.detailed),
          child: Text(l10n.detailedMode),
        ),
      ],
    ),
  );
}

/// Batch import for the legacy scene library. The saved JSON stays compatible
/// with its existing card readers while retaining the relationship summary.
Future<void> showSceneBatchImportPage(
  BuildContext context, {
  required SceneBatchImportKind kind,
  required List<Map<String, dynamic>> worldviews,
  List<Map<String, dynamic>> relationshipCandidates = const [],
  SceneImportDetailMode detailMode = SceneImportDetailMode.detailed,
  required VoidCallback onSaved,
  ResourceLibraryMode mode = ResourceLibraryMode.adventure,
}) {
  final l10n = _l10n(context);
  return showFormSubPage<void>(
    context: context,
    title: kind == SceneBatchImportKind.character
        ? l10n.sceneBatchImportCharacterTitle
        : l10n.sceneBatchImportNpcTitle,
    maxWidth: 1040,
    builder: (_) => _SceneBatchImportPage(
      kind: kind,
      worldviews: worldviews,
      relationshipCandidates: relationshipCandidates,
      detailMode: detailMode,
      onSaved: onSaved,
      mode: mode,
    ),
  );
}

class _SceneBatchImportPage extends ConsumerStatefulWidget {
  final SceneBatchImportKind kind;
  final List<Map<String, dynamic>> worldviews;
  final List<Map<String, dynamic>> relationshipCandidates;
  final SceneImportDetailMode detailMode;
  final VoidCallback onSaved;
  final ResourceLibraryMode mode;

  const _SceneBatchImportPage({
    required this.kind,
    required this.worldviews,
    this.relationshipCandidates = const [],
    this.detailMode = SceneImportDetailMode.detailed,
    required this.onSaved,
    required this.mode,
  });

  @override
  ConsumerState<_SceneBatchImportPage> createState() =>
      _SceneBatchImportPageState();
}

class _SceneBatchImportPageState extends ConsumerState<_SceneBatchImportPage> {
  final _source = TextEditingController();
  late final TextEditingController _minimumLength;
  late final TextEditingController _maximumLength;
  String? _worldviewId;
  String? _error;
  var _loading = false;
  final Set<String> _relatedResourceIds = {};
  late final String _idempotencyKey;

  List<Map<String, dynamic>> get _availableRelationshipCandidates =>
      WorldviewCharacterScopePolicy.filterSceneResources(
        widget.relationshipCandidates,
        _worldviewId,
      );

  void _selectWorldview(String? worldviewId) {
    setState(() {
      _worldviewId = worldviewId;
      final allowedIds = _availableRelationshipCandidates
          .map((item) => item['id']?.toString() ?? '')
          .toSet();
      _relatedResourceIds.removeWhere((id) => !allowedIds.contains(id));
    });
  }

  @override
  void initState() {
    super.initState();
    _idempotencyKey = 'scene_batch_${DateTime.now().microsecondsSinceEpoch}';
    final npc = widget.kind == SceneBatchImportKind.npc;
    _minimumLength = TextEditingController(
      text:
          '${npc ? ResourceLimits.sceneBatchNpcMinimumCharacters : ResourceLimits.sceneBatchCharacterMinimumCharacters}',
    );
    _maximumLength = TextEditingController(
      text:
          '${npc ? ResourceLimits.sceneBatchNpcMaximumCharacters : ResourceLimits.sceneBatchCharacterMaximumCharacters}',
    );
  }

  @override
  void dispose() {
    _source.dispose();
    _minimumLength.dispose();
    _maximumLength.dispose();
    super.dispose();
  }

  Future<void> _startRuntime() async {
    final source = _source.text.trim();
    if (source.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final world = widget.worldviews
          .where((item) => item['id'] == _worldviewId)
          .firstOrNull;
      final reference = StringBuffer(source);
      final worldview = world?['description']?.toString().trim() ?? '';
      if (worldview.isNotEmpty) {
        reference.write('\n\n所属世界观：\n$worldview');
      }
      final related = _availableRelationshipCandidates.where(
        (item) => _relatedResourceIds.contains(item['id']?.toString()),
      );
      if (related.isNotEmpty) {
        reference.write('\n\n关联角色：\n');
        for (final item in related) {
          reference.writeln(
            '${item['name'] ?? '未命名'}：${item['description'] ?? item['summary'] ?? ''}',
          );
        }
      }
      reference.write('\n\n${widget.detailMode.instruction}');
      reference.write('\n请由蓝图规划识别资料中的候选人物，并为每个候选建立稳定的 Part identity。');
      final minimum = int.tryParse(_minimumLength.text) ?? 0;
      final maximum = int.tryParse(_maximumLength.text) ?? 0;
      final target = maximum >= minimum && maximum > 0 ? maximum : minimum;
      final runtime = ref.read(resourceStudioRuntimeProvider);
      final l10n = _l10n(context);
      final plan = await runtime.createAndPlan(
        ResourceStudioCreationDraft(
          type: widget.kind == SceneBatchImportKind.npc
              ? ResourceType.npc
              : ResourceType.character,
          name: widget.kind == SceneBatchImportKind.npc
              ? l10n.sceneBatchImportNpcTitle
              : l10n.sceneBatchImportCharacterTitle,
          referenceSource: ReferenceSource.text(
            reference.toString(),
            label: 'scene batch import',
          ),
          targetCharacters: target > 0 ? target : 3000,
          origin: 'scene-batch-import',
          libraryMode: widget.mode.storageValue,
          idempotencyKey: _idempotencyKey,
        ),
      );
      if (!mounted) return;
      final candidates = plan.blueprint.allParts
          .map(
            (part) => SceneBatchCandidate(
              sourceId: part.id,
              displayName: part.title,
            ),
          )
          .toList(growable: false);
      final selected = await AppRouter.push<List<SceneBatchCandidate>>(
        context,
        pageBuilder: (_) => SceneBatchCandidateSelectPage(
          candidates: candidates,
        ),
      );
      if (!mounted || selected == null) return;
      final identity = await runtime.confirmAndStart(
        plan.creationSessionId,
        selectedPartIds:
            selected.map((candidate) => candidate.sourceId).toSet(),
      );
      if (!mounted) return;
      await AppRouter.push<void>(
        context,
        pageBuilder: (_) => ResourceStudioPage(
          resourceId: identity.resourceId.value,
          sessionId: identity.generationSessionId,
        ),
      );
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectRelatedCharacters() async {
    final l10n = _l10n(context);
    final selected = await showFormSubPage<Set<String>>(
      context: context,
      title: l10n.relateExistingCharactersTitle,
      maxWidth: 720,
      builder: (_) => _SceneRelationshipPickerPage(
        candidates: _availableRelationshipCandidates,
        selectedIds: _relatedResourceIds,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _relatedResourceIds
        ..clear()
        ..addAll(selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final importController = ref.watch(sceneBatchImportControllerProvider);
    final label = widget.kind == SceneBatchImportKind.character
        ? l10n.resourceTypeCharacter
        : l10n.resourceTypeNpc;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      children: [
        Text(l10n.provideCharacterDataTitle,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(l10n.batchAiRecognitionTip,
            style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 20),
        if (widget.worldviews.isNotEmpty) ...[
          NarrAItorDropdown<String>(
            value: _worldviewId,
            label: l10n.belongingWorldviewOptional,
            options: [
              NarrAItorDropdownOption(
                  value: null, label: l10n.notSpecifiedOption),
              ...widget.worldviews.map((item) => NarrAItorDropdownOption(
                  value: item['id']?.toString(),
                  label: item['name']?.toString() ?? l10n.unnamedWorldview)),
            ],
            onChanged: _selectWorldview,
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 18),
        Text(l10n.relateCharactersOptional,
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _availableRelationshipCandidates.isEmpty
              ? null
              : _selectRelatedCharacters,
          icon: const Icon(Icons.group_add_outlined),
          label: Text(_relatedResourceIds.isEmpty
              ? (_worldviewId == null
                  ? l10n.pleaseSelectWorldviewFirst
                  : l10n.selectRelatedCharacters)
              : l10n.relatedCharactersCount(_relatedResourceIds.length)),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _minimumLength,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: l10n.minTotalCharactersLabel,
                  border: const OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _maximumLength,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: l10n.maxTotalCharactersLabel,
                  border: const OutlineInputBorder()),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        TextField(
          controller: _source,
          minLines: 14,
          maxLines: 24,
          decoration: InputDecoration(
            labelText: l10n.characterDataLabel(label),
            hintText: l10n.characterDataHint(label),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        if ((_error ?? importController.errorMessage) != null) ...[
          const SizedBox(height: 10),
          Text(_error ?? importController.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _loading ? null : _startRuntime,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.person_search_outlined),
            label:
                Text(_loading ? l10n.planningAction : l10n.enterAiStudioAction),
          ),
        ),
      ],
    );
  }
}

class SceneBatchCandidateSelectPage extends StatefulWidget {
  final List<SceneBatchCandidate> candidates;

  const SceneBatchCandidateSelectPage({
    super.key,
    required this.candidates,
  });

  @override
  State<SceneBatchCandidateSelectPage> createState() =>
      _SceneBatchCandidateSelectPageState();
}

class _SceneBatchCandidateSelectPageState
    extends State<SceneBatchCandidateSelectPage> {
  late final Set<String> _selectedIds =
      widget.candidates.map((candidate) => candidate.sourceId).toSet();

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return Scaffold(
      appBar: AppBar(
          title: Text(
              l10n.selectCandidatesToImportTitle(widget.candidates.length))),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                itemCount: widget.candidates.length,
                itemBuilder: (context, index) {
                  final candidate = widget.candidates[index];
                  return CheckboxListTile(
                    value: _selectedIds.contains(candidate.sourceId),
                    title: Text(candidate.displayName),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selectedIds.add(candidate.sourceId);
                      } else {
                        _selectedIds.remove(candidate.sourceId);
                      }
                    }),
                  );
                },
              ),
            ),
            Material(
              elevation: 3,
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _selectedIds.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(
                                widget.candidates
                                    .where((candidate) => _selectedIds
                                        .contains(candidate.sourceId))
                                    .toList(growable: false),
                              ),
                      icon: const Icon(Icons.download_done_rounded),
                      label: Text(l10n
                          .importSelectedCharactersAction(_selectedIds.length)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SceneRelationshipPickerPage extends StatefulWidget {
  final List<Map<String, dynamic>> candidates;
  final Set<String> selectedIds;

  const _SceneRelationshipPickerPage({
    required this.candidates,
    required this.selectedIds,
  });

  @override
  State<_SceneRelationshipPickerPage> createState() =>
      _SceneRelationshipPickerPageState();
}

class _SceneRelationshipPickerPageState
    extends State<_SceneRelationshipPickerPage> {
  late final Set<String> _selected = Set<String>.from(widget.selectedIds);

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(l10n.selectCandidatesMultiTitle,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l10n.candidatesRelationTip,
            style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 16),
        for (final item in widget.candidates)
          CheckboxListTile(
            value: _selected.contains(item['id']?.toString()),
            title: Text(item['name']?.toString() ?? ''),
            onChanged: item['id'] == null
                ? null
                : (value) => setState(() {
                      final id = item['id'].toString();
                      if (value == true) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    }),
          ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context, _selected),
            icon: const Icon(Icons.check_rounded),
            label: Text(l10n.confirmRelateCharactersAction(_selected.length)),
          ),
        ),
      ],
    );
  }
}
