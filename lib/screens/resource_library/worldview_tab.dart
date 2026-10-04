import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../providers/riverpod_providers.dart';
import '../../core/config/generation_limits.dart';
import '../../models/resource_library_mode.dart';
import '../../core/widgets/form_sub_page_scaffold.dart';
import '../../core/widgets/workbench_chrome.dart';
import '../../core/widgets/tracked_state_definition_editor_section.dart';
import '../../models/tracked_state_definition.dart';
import '../../models/worldview_details.dart';
import '../../core/feedback/app_feedback.dart';
import '../../core/localization/app_error_localizer.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../application/resource_library/edit_drafts.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_zh.dart';
import 'worldview_ai_import_page.dart';
import 'resource_operation_feedback.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

String _worldviewModuleLabel(String key, AppLocalizations l10n) =>
    switch (worldviewModuleType(key)) {
      WorldviewModuleType.worldRules => l10n.worldviewModuleRules,
      WorldviewModuleType.worldState => l10n.worldviewModuleState,
      WorldviewModuleType.locations => l10n.worldviewModuleLocations,
      WorldviewModuleType.factions => l10n.worldviewModuleFactions,
      WorldviewModuleType.customsAndLife => l10n.worldviewModuleCustoms,
      WorldviewModuleType.timeline => l10n.worldviewModuleTimeline,
      WorldviewModuleType.glossary => l10n.worldviewModuleGlossary,
      WorldviewModuleType.creativeConstraints =>
        l10n.worldviewModuleConstraints,
      WorldviewModuleType.unknown => key,
    };

/// 世界观列表 + 手动编辑子页面 + AI 导入子页面
class WorldviewTab {
  /// 手动创建/编辑世界观子页面。
  static Future<void> showEdit(BuildContext context,
      Map<String, dynamic>? existing, VoidCallback onChanged,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure,
      WorldviewEditingMode editingMode = WorldviewEditingMode.simple}) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _WorldviewEditPage(
          existing: existing,
          onChanged: onChanged,
          mode: mode,
          editingMode: editingMode,
        ),
      ),
    );
  }

  /// AI 导入世界观弹窗
  static void showAiImport(BuildContext context, VoidCallback onChanged,
      List<Map<String, dynamic>> worldviewList,
      {ResourceLibraryMode mode = ResourceLibraryMode.adventure}) {
    final l10n = _l10n(context);
    showFormSubPage<void>(
      context: context,
      title: l10n.worldviewAiAssistantTitle,
      maxWidth: 840,
      builder: (_) => WorldviewAiImportPage(
        mode: mode,
        onChanged: onChanged,
      ),
    );
  }
}

/// 世界观手动创建/编辑表单。
///
/// The toolbar Save and the footer Save call the same [_persist], guarded by the
/// same [_saving] flag, so they share exactly one save authority and a rapid tap
/// on either can never race the other into a second write.
///
/// The form owns its controllers in a [State] so they are disposed only after
/// the route has left the tree, not while its exit transition is still
/// rebuilding the fields.
class _WorldviewEditPage extends StatefulWidget {
  const _WorldviewEditPage({
    required this.existing,
    required this.onChanged,
    required this.mode,
    required this.editingMode,
  });

  final Map<String, dynamic>? existing;
  final VoidCallback onChanged;
  final ResourceLibraryMode mode;
  final WorldviewEditingMode editingMode;

  @override
  State<_WorldviewEditPage> createState() => _WorldviewEditPageState();
}

class _WorldviewEditPageState extends State<_WorldviewEditPage> {
  late final WorldviewEditDraft draft;
  late final WorldviewEditingMode effectiveEditingMode;
  late final TextEditingController nameCtrl;
  late final TextEditingController descCtrl;
  late final Map<String, TextEditingController> moduleCtrls;
  late List<TrackedStateDefinition> trackedStateDefinitions;

  WorkbenchSavePhase _savePhase = WorkbenchSavePhase.idle;
  bool _saving = false;
  String _lastErrorMessage = '';
  String? _validationError;

  @override
  void initState() {
    super.initState();
    draft = WorldviewEditDraft.fromExisting(widget.existing,
        editingMode: widget.editingMode);
    effectiveEditingMode = draft.mode;
    nameCtrl = TextEditingController(text: draft.name)..addListener(_markDirty);
    descCtrl = TextEditingController(text: draft.description)
      ..addListener(_markDirty);
    moduleCtrls = <String, TextEditingController>{
      for (final key
          in WorldviewDetails.moduleKeys.where((key) => key != 'overview'))
        key: TextEditingController(text: draft.moduleTexts[key] ?? '')
          ..addListener(_markDirty),
    };
    trackedStateDefinitions =
        List<TrackedStateDefinition>.from(draft.trackedStateDefinitions);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    for (final controller in moduleCtrls.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Marks the form dirty after any persisted field changes.
  void _markDirty() {
    if (!mounted || _saving) return;
    if (_savePhase == WorkbenchSavePhase.dirty) return;
    setState(() => _savePhase = WorkbenchSavePhase.dirty);
  }

  /// The one save authority shared by the toolbar and footer buttons.
  Future<bool> _persist() async {
    if (_saving) return false;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return false;
    final l10n = _l10n(context);
    draft.name = name;
    draft.description = descCtrl.text.trim();
    for (final entry in moduleCtrls.entries) {
      draft.moduleTexts[entry.key] = entry.value.text.trim();
    }
    draft.trackedStateDefinitions = trackedStateDefinitions;

    setState(() {
      _saving = true;
      _savePhase = WorkbenchSavePhase.saving;
    });
    try {
      final result = await ProviderScope.containerOf(context, listen: false)
          .read(resourceCrudControllerProvider)
          .saveWorldviewDraft(draft, mode: widget.mode);
      if (!mounted) return false;
      if (!result.success) {
        final message = result.error == null
            ? (result.errorMessage ?? l10n.errorUnknown)
            : localizeAppError(l10n, result.error!);
        debugPrint('[WorldviewEditor] 保存世界观失败: ${result.errorMessage}');
        setState(() {
          _savePhase = WorkbenchSavePhase.failed;
          _lastErrorMessage = l10n.characterCardSaveFailed(message);
          _validationError = _lastErrorMessage;
        });
        return false;
      }
      setState(() {
        _savePhase = WorkbenchSavePhase.saved;
        _lastErrorMessage = '';
        _validationError = null;
      });
      return true;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveFromToolbar() async {
    final ok = await _persist();
    if (!mounted) return;
    final l10n = _l10n(context);
    if (ok) {
      AppFeedback.success(context, l10n.savedAction);
    } else if (_savePhase == WorkbenchSavePhase.failed) {
      AppFeedback.error(
        context,
        _lastErrorMessage.isEmpty ? l10n.saveFailedAction : _lastErrorMessage,
      );
    }
  }

  Future<void> _saveAndClose() async {
    final ok = await _persist();
    if (!mounted || !ok) return;
    Navigator.pop(context);
    widget.onChanged();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final l10n = _l10n(context);
    final crud = ProviderScope.containerOf(context, listen: false)
        .read(resourceCrudControllerProvider);
    final confirm = await AppConfirmDialog.show(
      context: context,
      title: l10n.characterCardConfirmDeleteTitle,
      message: l10n.worldviewConfirmDeleteMessage(existing['name'] ?? ''),
      confirmLabel: l10n.deleteAction,
      isDanger: true,
      icon: 'delete',
    );
    if (!confirm || !mounted) return;
    final result = await crud.deleteWorldviewPreset(
      existing['id'] as String,
      mode: widget.mode,
    );
    if (!result.success) {
      debugPrint('[WorldviewEditor] 删除世界观失败: ${result.errorMessage}');
      if (mounted) AppFeedback.error(context, l10n.worldviewDeleteFailed);
      return;
    }
    if (mounted) showResourceOperationSuccess(context, result, l10n);
    if (mounted) Navigator.pop(context);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return FormSubPageScaffold(
      title: widget.existing == null
          ? l10n.worldviewCreateTitle
          : l10n.worldviewEditTitle,
      maxWidth: 760,
      actions: [
        WorkbenchSaveAction(
          key: const Key('worldview-save-action'),
          phase: _savePhase,
          onPressed: _saveFromToolbar,
          saveLabel: l10n.saveAction,
          savedLabel: l10n.savedAction,
          savingLabel: l10n.savingAction,
          failedLabel: l10n.saveFailedAction,
        ),
      ],
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    effectiveEditingMode == WorldviewEditingMode.detailed
                        ? l10n.worldviewDetailedTitle
                        : l10n.worldviewInfoSection,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                        labelText: l10n.nameLabel,
                        border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                TextField(
                    controller: descCtrl,
                    maxLines:
                        effectiveEditingMode == WorldviewEditingMode.detailed
                            ? 4
                            : 6,
                    decoration: InputDecoration(
                        labelText: effectiveEditingMode ==
                                WorldviewEditingMode.detailed
                            ? l10n.worldviewOverviewDetailed
                            : l10n.worldviewOverviewConcise,
                        alignLabelWithHint: true,
                        border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                if (effectiveEditingMode == WorldviewEditingMode.detailed) ...[
                  Text(
                      l10n.worldviewDetailedLimitTip(
                          GenerationLimits.detailedWorldviewMaximumCharacters),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...moduleCtrls.entries.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: entry.value,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: _worldviewModuleLabel(
                              entry.key,
                              l10n,
                            ),
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      )),
                ],
                const SizedBox(height: 16),
                TrackedStateDefinitionEditorSection(
                  initialItems: trackedStateDefinitions,
                  onChanged: (items) {
                    setState(() => trackedStateDefinitions = items);
                    _markDirty();
                  },
                ),
                if (_validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_validationError!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                const SizedBox(height: 16),
                Row(children: [
                  if (widget.existing != null)
                    TextButton(
                        onPressed: _delete,
                        child: Text(l10n.deleteAction,
                            style: const TextStyle(color: Colors.red))),
                  const Spacer(),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(l10n.cancelAction)),
                  const SizedBox(width: 8),
                  FilledButton(
                      onPressed: _savePhase == WorkbenchSavePhase.saving
                          ? null
                          : () => unawaited(_saveAndClose()),
                      child: Text(l10n.saveAction)),
                ]),
              ]),
        ),
      ),
    );
  }
}
