import 'package:flutter/material.dart';
import '../../application/resource_library/import_models.dart';
import '../../application/resources/resource_creation_contracts.dart';
import '../../core/config/generation_limits.dart';
import '../../core/router/app_router.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../models/resource_library_mode.dart';
import '../../models/resource_provenance.dart';
import '../../application/resource_library/character_reference_context_mapper.dart';
import '../../core/utils/worldview_character_scope_policy.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../features/resource_studio/presentation/pages/resource_studio_page.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

class ResourceCardAiImportPage extends StatefulWidget {
  final ResourceCardImportKind kind;
  final List<Map<String, dynamic>> worldviews;
  final List<Map<String, dynamic>> characterCards;
  final String detailInstruction;
  final AiGenerationDepth aiDepth;
  final String? initialWorldviewId;
  final ResourceLibraryMode mode;
  final VoidCallback onChanged;

  const ResourceCardAiImportPage({
    super.key,
    required this.kind,
    required this.worldviews,
    required this.characterCards,
    required this.detailInstruction,
    required this.aiDepth,
    this.initialWorldviewId,
    required this.mode,
    required this.onChanged,
  });

  @override
  State<ResourceCardAiImportPage> createState() =>
      _ResourceCardAiImportPageState();
}

class _ResourceCardAiImportPageState extends State<ResourceCardAiImportPage> {
  final TextEditingController _source = TextEditingController();
  String? _worldviewId;
  final Set<String> _selectedIds = {};
  bool _autoSave = true;
  int _targetTotalCharacters =
      GenerationLimits.detailedCharacterDefaultCharacters;

  bool _openingStudio = false;
  bool get _busy => _openingStudio;

  @override
  void initState() {
    super.initState();
    _worldviewId = widget.initialWorldviewId;
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _scopedCards =>
      WorldviewCharacterScopePolicy.orderByOriginCompatibility(
        widget.characterCards,
        _worldviewId,
      );

  List<Map<String, String>> _associatedCharacters() =>
      CharacterReferenceContextMapper.fromStoredRows(
        cards: _scopedCards,
        selectedIds: _selectedIds,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Worldview dropdown (optional)
            if (widget.worldviews.isNotEmpty) ...[
              NarrAItorDropdown<String>(
                value: _worldviewId,
                label: l10n.associateWorldviewOptional,
                enabled: !_busy,
                options: [
                  NarrAItorDropdownOption(
                      value: null, label: l10n.notSpecifiedOption),
                  ...widget.worldviews.map((item) => NarrAItorDropdownOption(
                        value: item['id']?.toString(),
                        label:
                            item['name']?.toString() ?? l10n.unnamedWorldview,
                      ))
                ],
                onChanged: (value) => setState(() {
                  _worldviewId = value;
                }),
              ),
              const SizedBox(height: 12),
            ],
            // Existing characters multi‑select
            NarrAItorMultiSelectDropdown<String>(
              values: _selectedIds,
              label: l10n.relateCharactersOptional,
              emptyText: l10n.noExistingCharacterCards,
              selectedBuilder: (values) => values.isEmpty
                  ? l10n.notSpecifiedOption
                  : l10n.selectedCharactersCount(values.length),
              options: _scopedCards
                  .map((card) => NarrAItorDropdownOption(
                        value: card['id']?.toString() ?? '',
                        label: card['name']?.toString() ??
                            l10n.characterCardUnnamed,
                      ))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (values) => setState(() {
                        _selectedIds
                          ..clear()
                          ..addAll(values);
                      }),
            ),
            const SizedBox(height: 12),
            // Source text field
            TextField(
              controller: _source,
              minLines: 8,
              maxLines: 16,
              enabled: !_busy,
              decoration: InputDecoration(
                hintText: l10n.pasteCharacterRawTextHint,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.kind == ResourceCardImportKind.character &&
                widget.aiDepth == AiGenerationDepth.detailed) ...[
              Text(
                l10n.characterCardTargetValidChars(_targetTotalCharacters,
                    GenerationLimits.detailedCharacterMaximumCharacters),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Slider(
                value: _targetTotalCharacters.toDouble(),
                min: GenerationLimits.detailedCharacterMinimumCharacters
                    .toDouble(),
                max: GenerationLimits.detailedCharacterMaximumCharacters
                    .toDouble(),
                divisions: GenerationLimits.detailedCharacterTargetDivisions,
                label: '$_targetTotalCharacters',
                onChanged: _busy
                    ? null
                    : (value) => setState(
                          () => _targetTotalCharacters = value.round(),
                        ),
              ),
              Text(
                l10n.stagedDeepGenerationTip,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            // Auto‑save toggle
            SwitchListTile(
              title: Text(l10n.autoSaveToLibrary),
              value: _autoSave,
              onChanged: (v) => setState(() => _autoSave = v),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(l10n.cancelAction),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _generate,
                  child: Text(
                      _busy ? l10n.generatingEllipsis : l10n.aiAnalyzeAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    if (_openingStudio) return;
    final l10n = _l10n(context);
    final source = _source.text.trim();
    if (source.isEmpty) return;
    final selectedWorldview = widget.worldviews.firstWhere(
        (item) => item['id']?.toString() == _worldviewId,
        orElse: () => {});
    final reference = StringBuffer(source);
    final worldview = selectedWorldview['description']?.toString().trim() ?? '';
    if (worldview.isNotEmpty) {
      reference.write('\n\n关联世界观：\n$worldview');
    }
    final associated = _associatedCharacters();
    if (associated.isNotEmpty) {
      reference.write('\n\n关联角色：\n');
      for (final character in associated) {
        reference.writeln(character.entries
            .where((entry) => entry.value.trim().isNotEmpty)
            .map((entry) => '${entry.key}: ${entry.value}')
            .join('；'));
      }
    }
    if (widget.detailInstruction.trim().isNotEmpty) {
      reference.write('\n\n生成要求：${widget.detailInstruction.trim()}');
    }
    final firstLine = source.split(RegExp(r'\r?\n')).first.trim();
    final fallback = widget.kind == ResourceCardImportKind.character
        ? l10n.aiImportCharacterTitle
        : l10n.aiImportNpcTitle;
    setState(() => _openingStudio = true);
    try {
      await AppRouter.push<void>(
        context,
        pageBuilder: (_) => ResourceStudioPage(
          creationDraft: ResourceStudioCreationDraft(
            type: widget.kind == ResourceCardImportKind.character
                ? ResourceType.character
                : ResourceType.npc,
            name: firstLine.isEmpty
                ? fallback
                : (firstLine.length > 80
                    ? firstLine.substring(0, 80)
                    : firstLine),
            referenceSource: ReferenceSource.text(
              reference.toString(),
              label: '${widget.kind.name} import',
            ),
            targetCharacters: widget.kind == ResourceCardImportKind.character &&
                    widget.aiDepth == AiGenerationDepth.detailed
                ? _targetTotalCharacters
                : GenerationLimits.detailedCharacterMinimumCharacters,
            origin: 'resource-card-import',
            libraryMode: widget.mode.storageValue,
            originWorldviewId: _worldviewId ?? '',
          ),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _openingStudio = false);
    }
  }
}
