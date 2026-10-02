import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../core/widgets/workbench_section.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/tts/tts_models.dart';
import '../../../../domain/tts/tts_voices.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_en.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../settings/presentation/widgets/tts_voice_picker.dart';

/// Local read-aloud voice configuration for one Character / NPC resource.
///
/// This only writes the device-local voice binding store. It never touches the
/// character draft, resource metadata, resource tree, revisions or `updated_at`.
/// Worldview resources do not show this section.
class ResourceVoiceSettingSection extends ConsumerWidget {
  const ResourceVoiceSettingSection({
    super.key,
    required this.resourceId,
    required this.resourceName,
    required this.resourceType,
    this.embedded = false,
  });

  final ResourceId resourceId;
  final String resourceName;
  final ResourceType resourceType;
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (resourceType == ResourceType.worldview) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    final theme = Theme.of(context);
    final bindings = ref.watch(ttsVoiceBindingsProvider);
    final catalog = ref.watch(ttsModelCatalogProvider);
    final manager = ref.watch(ttsModelManagerProvider);
    final voiceId = bindings.preferences.bindingFor(resourceId.value);

    final voice = voiceId == null ? null : catalog.voiceById(voiceId);
    final model = voiceId == null
        ? null
        : catalog.modelForVoice(
            voiceId,
            isInstalled: (m) => manager.isModelInstalled(m.modelId),
          );
    final installed = model != null && manager.isModelInstalled(model.modelId);
    final display = voiceId == null
        ? l10n.readAloudVoiceAutoAssign
        : (voice?.displayName ?? voiceId);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          l10n.characterVoiceDescription,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(display, style: theme.textTheme.bodyMedium),
            ),
            TextButton(
              key: const ValueKey('resource-voice-choose'),
              onPressed: () => _choose(context, ref, voiceId),
              child: Text(l10n.readAloudVoiceChoose),
            ),
            if (voiceId != null)
              IconButton(
                onPressed: installed
                    ? () => ref.read(readAloudControllerProvider).playText(
                          l10n.ttsVoicePreviewSentence,
                          sourceId: 'tts-voice-preview',
                          voiceOverride: ReadAloudVoiceTarget(
                            backend: TtsBackendKind.neural,
                            capabilities: model.capabilities,
                            voiceId: voiceId,
                            modelId: model.modelId,
                            speakerId: voice!.speakerId,
                          ),
                        )
                    : null,
                visualDensity: VisualDensity.compact,
                tooltip: l10n.readAloudVoicePreview,
                icon: const AppSvgIcon('play', size: 18),
              ),
            if (voiceId != null)
              IconButton(
                key: const ValueKey('resource-voice-clear'),
                onPressed: () => bindings.clearBinding(resourceId.value),
                visualDensity: VisualDensity.compact,
                tooltip: l10n.readAloudVoiceClear,
                icon: const AppSvgIcon('close', size: 18),
              ),
          ],
        ),
        if (voiceId != null && !installed)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.ttsErrorModelUnavailable,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );

    if (embedded) {
      return WorkbenchSection(
        title: l10n.characterVoiceSectionTitle,
        child: content,
      );
    }
    return content;
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    String? currentVoiceId,
  ) async {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsEn();
    final selected = await showTtsVoicePicker(
      context,
      title: l10n.characterVoiceSectionTitle,
      showSystemOption: true,
      showAutoOption: true,
    );
    if (selected == null) return;
    final bindings = ref.read(ttsVoiceBindingsProvider);
    if (selected.isEmpty) {
      await bindings.clearBinding(resourceId.value);
    } else {
      await bindings.setBinding(resourceId.value, selected);
    }
  }
}
