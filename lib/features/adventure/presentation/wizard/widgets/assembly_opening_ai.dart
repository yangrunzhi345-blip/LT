import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/feedback/app_feedback.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/ui_foundation.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';
import '../../../../../models/adventure_config.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../widgets/app_dialogs.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// The assembly snapshot handed to the opening-generation LLM call.
///
/// It is captured through a builder so the AI always sees the *current*
/// worldview, roster, relationships and NPCs rather than a stale page load.
class OpeningAiContext {
  const OpeningAiContext({
    required this.config,
    this.worldviewDescription = '',
  });

  final AdventureConfig config;

  /// The worldview body the user sees/edits in the assembly page (the config's
  /// `worldview` field only carries the name).
  final String worldviewDescription;
}

/// A generated prologue: the opening narrative plus its initial action branches.
class OpeningAiOutcome {
  const OpeningAiOutcome({required this.scene, required this.options});

  final String scene;
  final List<String> options;
}

/// Default instruction used when the user leaves the prompt empty.
const String defaultOpeningAiPrompt =
    '请根据世界观和当前登场角色的性格、身份及羁绊关系，设计一个引人入胜的冒险序章开幕与3个极具代入感的初始行动抉择';

/// Calls the existing adventure AI authority to write a prologue.
///
/// This is the single UI-side entry point for opening generation: it never
/// talks to the LLM service directly and never re-implements the retry/parse
/// logic living in `AdventureAiController` / `AdventureAiUseCase`.
///
/// Returns null when generation failed (the controller already normalized the
/// error); callers must leave the user's existing content untouched in that case.
Future<OpeningAiOutcome?> generateOpeningWithAi({
  required WidgetRef ref,
  required String prompt,
  required OpeningAiContext context,
}) async {
  final config = context.config;
  final protagonist = config.protagonistCharacter;
  final protagonistCard =
      protagonist?.characterCardJson ?? const <String, dynamic>{};

  final result = await ref.read(adventureAiControllerProvider).generateOpening(
        userPrompt: prompt.isNotEmpty ? prompt : defaultOpeningAiPrompt,
        worldview: buildOpeningWorldviewText(
          config,
          context.worldviewDescription,
        ),
        protagonistName: protagonist?.characterName ?? config.name,
        protagonistRole: protagonist?.effectiveRole ?? config.protagonistClass,
        protagonistPersonality: _firstText([
          protagonistCard['personality'],
          config.personality,
        ]),
        protagonistBackground: _firstText([
          protagonistCard['description'],
          protagonistCard['background'],
          config.protagonistBackground,
        ]),
        protagonistBodyDescription: _firstText([
          protagonistCard['bodyDescription'],
          protagonistCard['customBodyDescription'],
        ]),
        protagonistAppearance: _text(protagonistCard['appearance']),
        selectedCharacters: buildOpeningCharacterContexts(config),
        characterRelationships: buildOpeningRelationshipContexts(config),
        npcs: buildOpeningNpcContexts(config),
      );

  if (result == null) return null;

  final scene = (result['scene'] ?? '').trim();
  final options = (result['options'] ?? '')
      .split('\n')
      .map((line) => line.replaceFirst(RegExp(r'^\d+[\.\s、]+'), '').trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (scene.isEmpty && options.isEmpty) return null;
  return OpeningAiOutcome(scene: scene, options: options);
}

/// Worldview name plus the full worldview body, so the model gets both the
/// label and the setting text (falls back to the snapshot description).
String buildOpeningWorldviewText(
  AdventureConfig config,
  String worldviewDescription,
) {
  final parts = <String>[];
  final name = config.worldview.trim();
  if (name.isNotEmpty) parts.add('世界名称：$name');
  final body = worldviewDescription.trim().isNotEmpty
      ? worldviewDescription.trim()
      : _text(config.worldviewSnapshot?['description']);
  if (body.isNotEmpty) parts.add('世界设定：$body');
  return parts.isEmpty ? '未知世界' : parts.join('\n');
}

/// Selected character cards (protagonist included), independent of NPCs.
List<Map<String, String>> buildOpeningCharacterContexts(
    AdventureConfig config) {
  return config.selectedCharacters.map((character) {
    final card = character.characterCardJson ?? const <String, dynamic>{};
    return <String, String>{
      'name': character.characterName,
      'isProtagonist': character.isProtagonist ? 'true' : 'false',
      'role': character.effectiveRole,
      'profession': _firstText([
        card['profession'],
        card['occupation'],
        card['role'],
      ]),
      'personality': _text(card['personality']),
      'background': _firstText([card['description'], card['background']]),
      'gender': _text(card['gender']),
      'age': _text(card['age']),
      'appearance': _text(card['appearance']),
      'bodyDescription': _firstText([
        card['bodyDescription'],
        card['customBodyDescription'],
      ]),
    };
  }).toList(growable: false);
}

/// Character-to-character relationships, resolved to display names.
List<Map<String, String>> buildOpeningRelationshipContexts(
  AdventureConfig config,
) {
  String nameOf(String id) {
    for (final character in config.selectedCharacters) {
      if (character.characterId == id || character.id == id) {
        return character.characterName;
      }
    }
    return id;
  }

  return config.characterRelationships.map((relationship) {
    return <String, String>{
      'sourceName': nameOf(relationship.sourceCharacterId),
      'targetName': nameOf(relationship.targetCharacterId),
      'relationType': relationship.effectiveRelation,
      'description': relationship.description,
    };
  }).toList(growable: false);
}

/// The NPC assets chosen for this assembly.
List<Map<String, String>> buildOpeningNpcContexts(AdventureConfig config) {
  return config.npcSnapshots.map((npc) {
    final json = npc.npcJson;
    return <String, String>{
      'name': npc.name.isNotEmpty ? npc.name : _text(json['name']),
      'role':
          _firstText([json['role'], json['profession'], json['occupation']]),
      'personality': _text(json['personality']),
      'relation': _firstText([json['relation'], json['relationship']]),
    };
  }).toList(growable: false);
}

String _text(Object? value) => value?.toString().trim() ?? '';

String _firstText(List<Object?> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// Reusable "AI 自动编写序章" panel for the assembly pages.
///
/// Owns only its generating/error state; the host page owns the prompt text and
/// decides where the generated scene + branches are written, so both
/// [AssemblyCreatePage] and [AssemblyConfigPage] share one implementation.
class OpeningAiPanel extends ConsumerStatefulWidget {
  const OpeningAiPanel({
    super.key,
    required this.promptController,
    required this.contextBuilder,
    required this.onGenerated,
    this.title,
    this.description,
    this.promptKey = const Key('assembly-opening-ai-prompt-input'),
    this.generateKey = const Key('assembly-opening-ai-generate-button'),
    this.progressKey = const Key('assembly-opening-ai-progress'),
    this.errorKey = const Key('assembly-opening-ai-error'),
  });

  final TextEditingController promptController;

  /// Snapshots the assembly context at the moment generation starts.
  final OpeningAiContext Function() contextBuilder;

  /// Receives the generated scene + branches so the host writes its own fields.
  final ValueChanged<OpeningAiOutcome> onGenerated;

  final String? title;
  final String? description;
  final Key promptKey;
  final Key generateKey;
  final Key progressKey;
  final Key errorKey;

  @override
  ConsumerState<OpeningAiPanel> createState() => _OpeningAiPanelState();
}

class _OpeningAiPanelState extends ConsumerState<OpeningAiPanel> {
  bool _generating = false;
  bool _hasGenerated = false;
  String? _error;

  Future<void> _generate() async {
    if (_generating) return;

    final l10n = _l10n(context);
    final chat = ref.read(chatProvider);
    if (!chat.isKeyConfigured) {
      AppFeedback.info(context, l10n.configureApiKeyFirstForAi);
      showApiSettings(context);
      return;
    }

    setState(() {
      _generating = true;
      _error = null;
    });

    try {
      final outcome = await generateOpeningWithAi(
        ref: ref,
        prompt: widget.promptController.text.trim(),
        context: widget.contextBuilder(),
      );
      if (!mounted) return;

      if (outcome == null) {
        // 生成失败绝不清空用户已填写的序章与分支，只提示并允许重试。
        setState(() {
          _generating = false;
          _error = ref.read(adventureAiControllerProvider).errorMessage ??
              l10n.aiGenerationNoValidContent;
        });
        return;
      }

      setState(() {
        _generating = false;
        _error = null;
        _hasGenerated = true;
      });
      widget.onGenerated(outcome);
      AppFeedback.success(context, l10n.aiOpeningGeneratedSuccess);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generating = false;
        _error = l10n.aiGenerationFailed(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = _l10n(context);

    return AppFormSection(
      title: widget.title ?? l10n.aiOpeningPanelTitle,
      description: widget.description ?? l10n.aiOpeningPanelDesc,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            key: widget.promptKey,
            controller: widget.promptController,
            label: l10n.openingPromptLabel,
            hintText: l10n.openingPromptHint,
            maxLines: 3,
            enabled: !_generating,
          ),
          const SizedBox(height: AppSpacing.sm),
          AppPrimaryButton(
            key: widget.generateKey,
            label: _hasGenerated
                ? l10n.regenerate
                : l10n.aiGenerateOpeningAndBranches,
            icon: Icons.auto_awesome_rounded,
            fullWidth: true,
            isLoading: _generating,
            onPressed: _generate,
          ),
          if (_generating) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.aiOpeningGeneratingProgress,
              key: widget.progressKey,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              key: widget.errorKey,
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
