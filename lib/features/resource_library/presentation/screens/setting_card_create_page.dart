import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/setting_cards/setting_card_reference_input.dart';
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
import '../widgets/setting_card_length_selector.dart';
import '../widgets/setting_card_reference_editor.dart';

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
  SettingCardReferenceMode _referenceMode = SettingCardReferenceMode.paste;
  SettingCardReferenceInput? _reference;
  SettingCardGenerationLength _length = SettingCardGenerationLength.standard;
  List<SettingCard> _worldviews = const <SettingCard>[];
  String _originWorldviewId = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadWorldviews);
  }

  Future<void> _loadWorldviews() async {
    try {
      final cards = await ref
          .read(settingCardServiceProvider)
          .list(kind: SettingCardKind.worldview);
      if (!mounted) return;
      setState(() => _worldviews = cards);
    } catch (_) {
      // The picker is optional context; a failed list must not block creation.
      if (mounted) setState(() => _worldviews = const <SettingCard>[]);
    }
  }

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
    String? createdId;
    try {
      final card = await service.create(
        kind: _kindOf(_type),
        name: name,
        summary: _summary.text.trim(),
        mode: widget.mode.storageValue,
        originWorldviewId:
            _type == ResourceType.worldview ? '' : _originWorldviewId,
      );
      createdId = card.id;
      if (generate) {
        await service.generate(
          id: card.id,
          instruction: instruction,
          reference: _reference,
          targetTotalCharacters: _length.targetCharacters,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop<String>(card.id);
    } on SettingCardGenerationException {
      // A failed first generation must not leave an empty draft in the
      // library; discardEmptyDraft only removes a card whose body is still
      // empty, so authored content is never touched.
      if (createdId != null) await service.discardEmptyDraft(createdId);
      if (mounted) {
        AppFeedback.error(context, _l10n(context).settingCardGenerateFailed);
      }
    } catch (error) {
      if (createdId != null) await service.discardEmptyDraft(createdId);
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
              if (_type != ResourceType.worldview) ...<Widget>[
                const SizedBox(height: AppSpacing.md),
                AppSelect<String>(
                  key: const Key('setting-card-create-origin-worldview'),
                  label: l10n.settingCardOriginWorldviewLabel,
                  value: _originWorldviewId,
                  enabled: !_busy,
                  items: <AppSelectItem<String>>[
                    AppSelectItem<String>(
                      value: '',
                      label: l10n.settingCardOriginWorldviewNone,
                    ),
                    for (final card in _worldviews)
                      AppSelectItem<String>(
                        value: card.id,
                        label: card.name.trim().isEmpty
                            ? _l10n(context).resourceUnnamed
                            : card.name.trim(),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _originWorldviewId = value ?? '');
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              SettingCardLengthSelector(
                key: const Key('setting-card-create-length'),
                keyPrefix: 'setting-card-create-length',
                value: _length,
                enabled: !_busy,
                onChanged: (value) => setState(() => _length = value),
              ),
              const SizedBox(height: AppSpacing.md),
              SettingCardReferenceEditor(
                mode: _referenceMode,
                enabled: !_busy,
                onModeChanged: (mode) => setState(() => _referenceMode = mode),
                onChanged: (reference) => _reference = reference,
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
