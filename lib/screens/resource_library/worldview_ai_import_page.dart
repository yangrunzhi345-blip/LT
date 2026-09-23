import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../controllers/resource_library_import_controller.dart';
import '../../core/router/app_router.dart';
import '../../core/widgets/narr_aitor_dropdown.dart';
import '../../models/resource_library_mode.dart';
import '../../models/worldview_details.dart';
import '../../providers/riverpod_providers.dart';
import '../../application/resources/resource_creation_contracts.dart';
import '../../domain/resources/resource_contracts.dart';
import '../../features/resource_studio/presentation/pages/resource_studio_page.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

class WorldviewAiImportPage extends ConsumerStatefulWidget {
  final ResourceLibraryMode mode;
  final VoidCallback onChanged;

  const WorldviewAiImportPage({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  @override
  ConsumerState<WorldviewAiImportPage> createState() =>
      _WorldviewAiImportPageState();
}

class _WorldviewAiImportPageState extends ConsumerState<WorldviewAiImportPage> {
  final TextEditingController sourceCtrl = TextEditingController();
  final TextEditingController targetCharactersCtrl =
      TextEditingController(text: '10000');
  var importMode = WorldviewEditingMode.simple;
  bool _autoSave = true;

  ResourceLibraryImportController get controller =>
      ref.read(resourceLibraryImportControllerProvider);

  bool get busy =>
      controller.phase == ResourceImportPhase.generating ||
      controller.phase == ResourceImportPhase.saving;

  @override
  void dispose() {
    sourceCtrl.dispose();
    targetCharactersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(resourceLibraryImportControllerProvider);
    final l10n = _l10n(context);
    final progress = controller.worldviewProgress;
    final error = controller.errorMessage;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.originalTextContent,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(l10n.worldviewAiImportTip,
                style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            const SizedBox(height: 12),
            TextField(
              controller: sourceCtrl,
              maxLines: 10,
              minLines: 5,
              enabled: !busy,
              decoration: InputDecoration(
                hintText: l10n.pasteOriginalTextHint,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            NarrAItorDropdown<WorldviewEditingMode>(
              value: importMode,
              label: l10n.importModeLabel,
              enabled: !busy,
              options: [
                NarrAItorDropdownOption(
                    value: WorldviewEditingMode.simple,
                    label: l10n.conciseMode),
                NarrAItorDropdownOption(
                    value: WorldviewEditingMode.detailed,
                    label: l10n.detailedMode),
              ],
              onChanged: (value) {
                if (value != null) setState(() => importMode = value);
              },
            ),
            if (busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress?.fraction),
              const SizedBox(height: 8),
              Text(
                progress == null
                    ? l10n.preparingDeduction
                    : progress.targetCharacters != null
                        ? l10n.deductionProgressChars(
                            progress.currentCharacters,
                            progress.targetCharacters!,
                            progress.partialText,
                          )
                        : l10n.deductionProgressStage(
                            progress.completedQuestions >=
                                    progress.totalQuestions
                                ? progress.totalQuestions
                                : progress.completedQuestions + 1,
                            progress.totalQuestions,
                            progress.partialText,
                          ),
                style: const TextStyle(fontSize: 12),
              ),
              if (progress?.partialText.trim().isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(progress!.partialText,
                      maxLines: 6, overflow: TextOverflow.ellipsis),
                ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            SwitchListTile(
              title: Text(l10n.autoSaveToLibrary),
              value: _autoSave,
              onChanged: (v) => setState(() => _autoSave = v),
            ),
            if (importMode == WorldviewEditingMode.detailed) ...[
              const SizedBox(height: 12),
              TextField(
                controller: targetCharactersCtrl,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.expectedTotalCharacters,
                  helperText: l10n.adaptiveStageHelperText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: Text(l10n.cancelAction),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy ? null : _generate,
                  child: Text(l10n.aiAnalyzeAction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generate() async {
    final l10n = _l10n(context);
    final target = importMode == WorldviewEditingMode.detailed
        ? int.tryParse(targetCharactersCtrl.text.trim())
        : null;
    final source = sourceCtrl.text.trim();
    if (source.isEmpty) return;
    final name = source.split(RegExp(r'\r?\n')).first.trim();
    await AppRouter.push<void>(
      context,
      pageBuilder: (_) => ResourceStudioPage(
        creationDraft: ResourceStudioCreationDraft(
          type: ResourceType.worldview,
          name: name.isEmpty
              ? l10n.worldviewCreateTitle
              : (name.length > 80 ? name.substring(0, 80) : name),
          referenceSource:
              ReferenceSource.text(source, label: l10n.worldviewCreateTitle),
          targetCharacters: target ?? 10000,
          origin: 'worldview-import',
          libraryMode: widget.mode.storageValue,
        ),
      ),
    );
    if (!mounted) return;
    Navigator.pop(context);
    widget.onChanged();
  }
}
