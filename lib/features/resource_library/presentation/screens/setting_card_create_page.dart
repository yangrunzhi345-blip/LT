import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/setting_cards/setting_card_service.dart';
import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_select.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/setting_cards/setting_card.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../models/resource_library_mode.dart';
import '../../../../providers/riverpod_providers.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// Lightweight creation flow: one document, optionally filled by one AI call.
final class SettingCardCreatePage extends ConsumerStatefulWidget {
  const SettingCardCreatePage({
    super.key,
    this.initialType = ResourceType.worldview,
    this.mode = ResourceLibraryMode.adventure,
  });

  final ResourceType initialType;
  final ResourceLibraryMode mode;

  @override
  ConsumerState<SettingCardCreatePage> createState() =>
      _SettingCardCreatePageState();
}

final class _SettingCardCreatePageState
    extends ConsumerState<SettingCardCreatePage> {
  late ResourceType _type = widget.initialType;
  final _name = TextEditingController();
  final _summary = TextEditingController();
  final _instruction = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool generate}) async {
    if (_busy) return;
    final name = _name.text.trim();
    final instruction = _instruction.text.trim();
    if (generate && instruction.isEmpty) {
      AppFeedback.warning(context, _l10n(context).settingCardGenerateHint);
      return;
    }
    setState(() => _busy = true);
    final service = ref.read(settingCardServiceProvider);
    try {
      final card = await service.create(
        kind: _kindOf(_type),
        name: name,
        summary: _summary.text.trim(),
        mode: widget.mode.storageValue,
      );
      if (generate) {
        await service.generate(id: card.id, instruction: instruction);
      }
      if (!mounted) return;
      Navigator.of(context).pop<String>(card.id);
    } on SettingCardGenerationException {
      if (mounted) {
        AppFeedback.error(context, _l10n(context).settingCardGenerateFailed);
      }
    } catch (error) {
      if (mounted) AppFeedback.error(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.resourceCreateTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.resourceManualCreationDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.lg),
              AppSelect<ResourceType>(
                key: const Key('setting-card-create-type'),
                label: l10n.resourceTypeSectionTitle,
                value: _type,
                enabled: !_busy,
                items: <AppSelectItem<ResourceType>>[
                  AppSelectItem(
                    value: ResourceType.worldview,
                    label: l10n.resourceTypeWorldview,
                  ),
                  AppSelectItem(
                    value: ResourceType.character,
                    label: l10n.resourceTypeCharacter,
                  ),
                  AppSelectItem(
                    value: ResourceType.npc,
                    label: l10n.resourceTypeNpc,
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                key: const Key('setting-card-create-name'),
                controller: _name,
                label: l10n.settingCardNameLabel,
                hintText: l10n.resourceManualNameHint,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                key: const Key('setting-card-create-summary'),
                controller: _summary,
                label: l10n.resourceSummaryOptionalLabel,
                hintText: l10n.resourceManualSummaryHint,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                key: const Key('setting-card-create-instruction'),
                controller: _instruction,
                label: l10n.settingCardGenerateHint,
                maxLines: 4,
                minLines: 3,
                enabled: !_busy,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  FilledButton(
                    key: const Key('setting-card-create-manual'),
                    onPressed: _busy ? null : () => _submit(generate: false),
                    child: Text(l10n.createAction),
                  ),
                  OutlinedButton(
                    key: const Key('setting-card-create-ai'),
                    onPressed: _busy ? null : () => _submit(generate: true),
                    child: Text(l10n.settingCardGenerateAction),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.cancelAction),
                  ),
                ],
              ),
              if (_busy) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static SettingCardKind _kindOf(ResourceType type) => switch (type) {
        ResourceType.worldview => SettingCardKind.worldview,
        ResourceType.character => SettingCardKind.character,
        ResourceType.npc => SettingCardKind.npc,
      };
}
