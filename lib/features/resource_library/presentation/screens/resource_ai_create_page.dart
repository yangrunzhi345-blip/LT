import 'package:flutter/material.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/resources/resource_creation_contracts.dart';
import '../../../../application/resource_library/character_generation_reference.dart';
import '../../../../core/feedback/app_feedback.dart';
import '../../../../domain/resources/character_relationship.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/resource_limits.dart';
import '../../../../core/widgets/ui_foundation.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../resolvers/resource_presentation_resolver.dart';
import '../widgets/resource_creation_flow.dart';
import 'resource_blueprint_review_page.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

enum AiReferenceMode {
  paste,
  file,
  existing,
}

final class _RelationshipEditor {
  _RelationshipEditor({required this.source})
      : relationType = CharacterRelationshipType.friend,
        sourceRole = TextEditingController(text: 'friend'),
        generatedRole = TextEditingController(text: 'friend'),
        description = TextEditingController();

  ResourceLibraryItem source;
  CharacterRelationshipType relationType;
  final TextEditingController sourceRole;
  final TextEditingController generatedRole;
  final TextEditingController description;

  void dispose() {
    sourceRole.dispose();
    generatedRole.dispose();
    description.dispose();
  }
}

/// AI 智能创建资源页面 [ResourceAiCreatePage]
///
/// 遵循 R02 导航优先架构，将旧版 AlertDialog 弹窗重构为全端标准独立页面：
/// - 资源类型与名称输入 (AppFormSection + AppSelect + AppTextField)
/// - 纯页面内参考资料选择 (粘贴 / 文件 / 已有资源)，消除嵌套弹窗
/// - 深度整合 Material 3 设计规范与 320px 响应式约束
/// - 支持蓝图规划与预览 (Blueprint Review) 及快速创建
class ResourceAiCreatePage extends ConsumerStatefulWidget {
  const ResourceAiCreatePage({
    super.key,
    this.initialType = ResourceType.worldview,
    this.resources = const [],
    this.lockedRelationshipSource,
  });

  final ResourceType initialType;
  final List<ResourceLibraryItem> resources;

  /// Optional source character supplied by the detail page. When present the
  /// first relationship reference is fixed to this resource and cannot be
  /// replaced by the user.
  final ResourceLibraryItem? lockedRelationshipSource;

  @override
  ConsumerState<ResourceAiCreatePage> createState() =>
      _ResourceAiCreatePageState();
}

class _ResourceAiCreatePageState extends ConsumerState<ResourceAiCreatePage> {
  final _nameController = TextEditingController();
  final _referenceController = TextEditingController();
  final _fileNameController = TextEditingController();

  /// Free-text companion of the target-word Slider. Kept in sync both ways so a
  /// value typed here reaches the generated request, and a value chosen on the
  /// Slider is reflected here.
  final _targetCharactersController = TextEditingController();
  final _targetInputFocusNode = FocusNode();

  late ResourceType _type;
  late int _targetCharacters;

  /// Error shown by the numeric target input. Only set while the field holds an
  /// unparseable value; a numeric out-of-range value is clamped instead.
  String? _targetInputError;
  AiReferenceMode _referenceMode = AiReferenceMode.paste;
  ResourceLibraryItem? _existingResource;
  ResourceLibraryItem? _originWorldview;
  final List<_RelationshipEditor> _relationshipEditors = [];
  String? _relationshipError;

  /// Guards against a double tap submitting the draft twice: the second tap
  /// must never pop a route twice.
  bool _submitting = false;

  String? _nameError;
  String? _referenceError;
  String? _fileNameError;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _targetCharacters = _maximumTargetFor(_type);
    _targetCharactersController.text = _targetCharacters.toString();
    _targetInputFocusNode.addListener(_handleTargetInputFocusChange);
    if (widget.resources.isNotEmpty) {
      _existingResource = widget.resources.first;
    }
    _ensureLockedRelationshipEditor();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _referenceController.dispose();
    _fileNameController.dispose();
    _targetCharactersController.dispose();
    _targetInputFocusNode
      ..removeListener(_handleTargetInputFocusChange)
      ..dispose();
    for (final editor in _relationshipEditors) {
      editor.dispose();
    }
    super.dispose();
  }

  bool _planning = false;

  ResourceStudioCreationDraft? _buildDraft() {
    final l10n = _l10n(context);
    final name = _nameController.text.trim();
    bool hasError = false;

    if (name.isEmpty) {
      setState(() => _nameError = l10n.resourceInputNameError);
      hasError = true;
    }

    ReferenceSource reference;
    switch (_referenceMode) {
      case AiReferenceMode.paste:
        final text = _referenceController.text.trim();
        if (text.isEmpty) {
          setState(
              () => _referenceError = l10n.resourceInputOrPasteReferenceError);
          hasError = true;
        }
        reference =
            ReferenceSource.text(text, label: l10n.resourcePastedContentLabel);

      case AiReferenceMode.file:
        final fileName = _fileNameController.text.trim();
        final text = _referenceController.text.trim();
        if (fileName.isEmpty) {
          setState(() => _fileNameError = l10n.resourceInputFileNameError);
          hasError = true;
        }
        if (text.isEmpty) {
          setState(() => _referenceError = l10n.resourceInputFileContentError);
          hasError = true;
        }
        reference = ReferenceSource.file(text, fileName: fileName);

      case AiReferenceMode.existing:
        final existing = _existingResource;
        if (existing == null || existing.id.isEmpty) {
          setState(() => _referenceError = l10n.resourceSelectExistingError);
          hasError = true;
        }
        reference = ReferenceSource.existingResource(
          existing?.id ?? '',
          label: existing?.name ?? '',
        );
    }

    if (_type == ResourceType.character || _type == ResourceType.npc) {
      final sourceIds = <String>{};
      try {
        for (final editor in _relationshipEditors) {
          if (!sourceIds.add(editor.source.id)) {
            throw const FormatException('duplicate relationship reference');
          }
          CharacterGenerationReference(
            sourceResourceId: ResourceId(editor.source.id),
            relationshipType: editor.relationType,
            sourceRole: editor.sourceRole.text,
            generatedCharacterRole: editor.generatedRole.text,
            description: editor.description.text,
            worldviewScope: editor.source.originWorldviewId,
          );
        }
        CharacterGenerationScopeValidator.validate(
          references: [
            for (final editor in _relationshipEditors)
              CharacterGenerationReference(
                sourceResourceId: ResourceId(editor.source.id),
                relationshipType: editor.relationType,
                sourceRole: editor.sourceRole.text,
                generatedCharacterRole: editor.generatedRole.text,
                description: editor.description.text,
                worldviewScope: editor.source.originWorldviewId,
              ),
          ],
          targetWorldviewId: _originWorldview?.id ?? '',
        );
        _relationshipError = null;
      } on CharacterGenerationScopeException catch (error) {
        _relationshipError = error.message;
        hasError = true;
      } on Object {
        _relationshipError = l10n.relationshipNetworkDescription;
        hasError = true;
      }
    }

    if (hasError) return null;

    final relationshipReferences = _relationshipEditors
        .map(
          (editor) => CharacterGenerationReference(
            sourceResourceId: ResourceId(editor.source.id),
            relationshipType: editor.relationType,
            sourceRole: editor.sourceRole.text,
            generatedCharacterRole: editor.generatedRole.text,
            name: editor.source.name,
            description: editor.description.text,
            worldviewScope: editor.source.originWorldviewId,
          ),
        )
        .toList(growable: false);

    return ResourceStudioCreationDraft(
      type: _type,
      name: name,
      referenceSource: reference,
      targetCharacters: _targetCharacters,
      originWorldviewId: _originWorldview?.id ?? '',
      relationshipDraft: relationshipReferences.isEmpty
          ? null
          : CharacterRelationshipDraft(
              relationship: CharacterGenerationRelationship.fromReferences(
                relationshipReferences,
              ),
            ),
    );
  }

  void _addRelationshipEditor() {
    final selectedIds = _relationshipEditors.map((editor) => editor.source.id);
    final source = _relationshipSourceChoices
        .where((candidate) => !selectedIds.contains(candidate.id))
        .firstOrNull;
    if (source == null) return;
    setState(() {
      _relationshipEditors.add(_RelationshipEditor(source: source));
    });
  }

  void _removeRelationshipEditor(int index) {
    final editor = _relationshipEditors[index];
    if (widget.lockedRelationshipSource?.id == editor.source.id) return;
    setState(() {
      _relationshipEditors.removeAt(index).dispose();
    });
  }

  List<ResourceLibraryItem> get _relationshipSourceChoices {
    final choices = <String, ResourceLibraryItem>{
      for (final resource in widget.resources)
        if (resource.type == ResourceType.character ||
            resource.type == ResourceType.npc)
          resource.id: resource,
    };
    final locked = widget.lockedRelationshipSource;
    if (locked != null) choices[locked.id] = locked;
    return choices.values.toList(growable: false);
  }

  String _relationshipTypeLabel(
    AppLocalizations l10n,
    CharacterRelationshipType type,
  ) =>
      switch (type) {
        CharacterRelationshipType.friend => l10n.relationFriend,
        CharacterRelationshipType.enemy => l10n.relationEnemy,
        CharacterRelationshipType.stranger => l10n.relationStranger,
        CharacterRelationshipType.companion => l10n.relationCompanion,
        CharacterRelationshipType.lover => l10n.relationLover,
        CharacterRelationshipType.mentorStudent => l10n.relationMentor,
        CharacterRelationshipType.rival => l10n.relationRival,
        CharacterRelationshipType.family ||
        CharacterRelationshipType.sibling ||
        CharacterRelationshipType.parentChild =>
          l10n.relationKin,
        CharacterRelationshipType.custom ||
        CharacterRelationshipType.employerEmployee ||
        CharacterRelationshipType.guardianWard =>
          l10n.relationCustom,
      };

  void _ensureLockedRelationshipEditor() {
    final locked = widget.lockedRelationshipSource;
    if (locked == null || _relationshipEditors.isNotEmpty) return;
    _relationshipEditors.add(_RelationshipEditor(source: locked));
  }

  void _submit() {
    if (_submitting || _planning) return;
    final draft = _buildDraft();
    if (draft == null) return;

    setState(() => _submitting = true);
    Navigator.of(context).pop(draft);
  }

  Future<void> _planBlueprint() async {
    if (_submitting || _planning) return;
    final draft = _buildDraft();
    if (draft == null) return;
    final l10n = _l10n(context);
    setState(() => _planning = true);

    try {
      final runtime = ref.read(resourceStudioRuntimeProvider);
      final plan = await runtime.createAndPlan(draft);
      if (!mounted) return;
      setState(() => _planning = false);
      final result = await Navigator.of(context).push<Object?>(
        MaterialPageRoute<Object?>(
          builder: (_) => ResourceBlueprintReviewPage(
            plan: plan,
            draft: draft,
          ),
        ),
      );
      if (!mounted) return;
      // The review page returns the persisted identity once the blueprint is
      // confirmed and generation has started. Bubble it to the host so the
      // whole finished creation flow (hub + this form + review) pops away and
      // the host opens the Studio — the same authority as the direct-submit
      // path. Backing out of the review returns null and keeps this form.
      if (result is ResourceAiCreationIdentity) {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _planning = false);
      AppFeedback.error(
        context,
        l10n.resourceDetailActionFailed(
          ResourcePresentationResolver.sanitize(error.toString(),
              fallback: l10n.resourceCreationFailedRetry),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    final typeItems = [
      for (final type in ResourceType.values)
        AppSelectItem<ResourceType>(
          value: type,
          label: resourceTypeLabel(type, l10n),
        ),
    ];

    final existingResourceItems = [
      for (final res in widget.resources)
        AppSelectItem<ResourceLibraryItem>(
          value: res,
          label: '${res.localizedTypeLabel(l10n)} · ${res.name}',
          subtitle: res.summary.isNotEmpty ? res.summary : null,
        ),
    ];
    final worldviewItems = [
      AppSelectItem<ResourceLibraryItem>(
        value: null,
        label: l10n.resourceNotSpecified,
      ),
      for (final worldview in widget.resources.where(
        (resource) => resource.type == ResourceType.worldview,
      ))
        AppSelectItem<ResourceLibraryItem>(
          value: worldview,
          label: worldview.name,
          subtitle: worldview.summary.isNotEmpty ? worldview.summary : null,
        ),
    ];

    return AppPageScaffold(
      title: l10n.resourceAiCreateTitle,
      maxWidth: 640,
      scrollable: true,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: l10n.resourceBasicInfoTitle,
              description: l10n.resourceAiBasicInfoDescription,
              children: [
                AppSelect<ResourceType>(
                  key: const Key('ai-create-type-select'),
                  label: l10n.resourceTypeSectionTitle,
                  value: _type,
                  items: typeItems,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _type = val;
                        if (val == ResourceType.worldview) {
                          _originWorldview = null;
                        }
                        _targetCharacters = _targetCharacters.clamp(
                          ResourceLimits.minimumGenerationTargetCharacters,
                          _maximumTargetFor(val),
                        );
                        _targetInputError = null;
                      });
                      _syncTargetCharactersController();
                    }
                  },
                ),
                AppTextField(
                  key: const Key('ai-create-name-field'),
                  controller: _nameController,
                  label: l10n.resourceNameLabel,
                  hintText: l10n.resourceAiNameHint,
                  errorText: _nameError,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_type == ResourceType.character || _type == ResourceType.npc)
              AppFormSection(
                title: l10n.resourceAssociateWorldviewTitle,
                description: l10n.resourceAssociateWorldviewDescription,
                children: [
                  if (worldviewItems.length == 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l10n.resourceNoAvailableWorldview,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  AppSelect<ResourceLibraryItem>(
                    key: const Key('ai-create-origin-worldview-select'),
                    label: l10n.resourceAssociateWorldviewTitle,
                    value: _originWorldview,
                    items: worldviewItems,
                    enabled: worldviewItems.length > 1,
                    onChanged: (value) {
                      setState(() => _originWorldview = value);
                    },
                  ),
                ],
              ),
            if (_type == ResourceType.character || _type == ResourceType.npc)
              const SizedBox(height: 12),
            if (_type == ResourceType.character || _type == ResourceType.npc)
              _buildRelationshipSection(l10n),
            if (_type == ResourceType.character || _type == ResourceType.npc)
              const SizedBox(height: 12),
            AppFormSection(
              title: l10n.resourceReferenceSourceTitle,
              description: l10n.resourceReferenceSourceDescription,
              children: [
                SegmentedButton<AiReferenceMode>(
                  key: const Key('ai-create-reference-segmented'),
                  segments: [
                    ButtonSegment(
                      value: AiReferenceMode.paste,
                      icon: const AppSvgIcon('copy', size: 18),
                      label: Text(l10n.resourceTabPaste),
                    ),
                    ButtonSegment(
                      value: AiReferenceMode.file,
                      icon: const AppSvgIcon('book', size: 18),
                      label: Text(l10n.resourceTabFile),
                    ),
                    ButtonSegment(
                      value: AiReferenceMode.existing,
                      icon: const AppSvgIcon('copy', size: 18),
                      label: Text(l10n.resourceTabExistingResource),
                    ),
                  ],
                  selected: {_referenceMode},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _referenceMode = selection.first;
                      _referenceError = null;
                      _fileNameError = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildReferenceContent(existingResourceItems, l10n),
              ],
            ),
            const SizedBox(height: 12),
            AppFormSection(
              title: l10n.resourceGenerationLengthTitle,
              description: l10n.resourceGenerationLengthDescription,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l10n.resourceTargetCharactersLabel)),
                    Text(
                      l10n.resourceTargetCharactersValue(_targetCharacters),
                      key: const Key('ai-create-target-value'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
                Slider(
                  key: const Key('ai-create-target-slider'),
                  value: _targetCharacters.toDouble(),
                  min: ResourceLimits.minimumGenerationTargetCharacters
                      .toDouble(),
                  max: _maximumTargetFor(_type).toDouble(),
                  divisions: _targetDivisionsFor(_type),
                  label: l10n.resourceTargetCharactersValue(_targetCharacters),
                  onChanged: (value) {
                    setState(() {
                      _targetCharacters = value.round();
                      _targetInputError = null;
                    });
                    _syncTargetCharactersController();
                  },
                ),
                Row(
                  children: [
                    Text(l10n.resourceLengthShort),
                    const Spacer(),
                    Text(l10n.resourceLengthLong),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AppTextField(
                        key: const ValueKey('ai_creation_target_words_input'),
                        controller: _targetCharactersController,
                        focusNode: _targetInputFocusNode,
                        hintText: l10n.resourceTargetCharactersLabel,
                        errorText: _targetInputError,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onChanged: _onTargetCharactersInputChanged,
                        onSubmitted: _commitTargetCharactersInput,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const ValueKey('ai_creation_target_words_confirm'),
                      tooltip: l10n.applyAction,
                      onPressed: () => _commitTargetCharactersInput(
                          _targetCharactersController.text),
                      icon: const AppSvgIcon('check', size: 20),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppPrimaryButton(
              key: const Key('ai-create-submit-button'),
              label: l10n.resourceStartCreateAction,
              iconWidget: const AppSvgIcon('generation'),
              fullWidth: true,
              isLoading: _submitting,
              onPressed: _submit,
            ),
            const SizedBox(height: 10),
            AppSecondaryButton(
              key: const Key('ai-create-plan-button'),
              label: l10n.resourceBlueprintPlanAction,
              iconWidget: const AppSvgIcon('graph'),
              fullWidth: true,
              isLoading: _planning,
              onPressed: _planBlueprint,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelationshipSection(AppLocalizations l10n) {
    final choices = _relationshipSourceChoices;
    return AppFormSection(
      title: l10n.relationshipNetworkTitle,
      description: l10n.relationshipNetworkDescription,
      children: [
        if (_relationshipEditors.isEmpty) Text(l10n.resourceNotSpecified),
        for (var index = 0; index < _relationshipEditors.length; index++)
          _buildRelationshipEditor(index, choices, l10n),
        if (_relationshipError != null)
          Text(
            _relationshipError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('ai-create-add-relationship'),
            onPressed: choices.isEmpty ? null : _addRelationshipEditor,
            icon: const AppSvgIcon('add', size: 18),
            label: Text(l10n.resourceCreateShort),
          ),
        ),
      ],
    );
  }

  Widget _buildRelationshipEditor(
    int index,
    List<ResourceLibraryItem> choices,
    AppLocalizations l10n,
  ) {
    final editor = _relationshipEditors[index];
    final isLocked = widget.lockedRelationshipSource?.id == editor.source.id;
    return Padding(
      key: ValueKey('ai-create-relationship-$index'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppSelect<ResourceLibraryItem>(
                  value: editor.source,
                  label: l10n.resourceTypeCharacter,
                  enabled: !isLocked,
                  items: [
                    for (final resource in choices)
                      AppSelectItem(
                        value: resource,
                        label: resource.localizedName(l10n),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => editor.source = value);
                  },
                ),
              ),
              if (!isLocked)
                IconButton(
                  tooltip: l10n.deleteAction,
                  icon: const AppSvgIcon('delete'),
                  onPressed: () => _removeRelationshipEditor(index),
                ),
            ],
          ),
          const SizedBox(height: 8),
          AppSelect<CharacterRelationshipType>(
            value: editor.relationType,
            label: l10n.relationshipLabel(''),
            items: [
              for (final type in CharacterRelationshipType.values)
                AppSelectItem(
                  value: type,
                  label: _relationshipTypeLabel(l10n, type),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                editor.relationType = value;
                _setDefaultRoles(editor);
              });
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: editor.sourceRole,
            decoration: InputDecoration(labelText: l10n.relationDetailsHint),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: editor.generatedRole,
            decoration: InputDecoration(labelText: l10n.relationDetailsHint),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: editor.description,
            decoration: InputDecoration(labelText: l10n.relationDetailsHint),
            minLines: 2,
            maxLines: 4,
          ),
          const Divider(),
        ],
      ),
    );
  }

  void _setDefaultRoles(_RelationshipEditor editor) {
    final roles = switch (editor.relationType) {
      CharacterRelationshipType.mentorStudent => ('mentor', 'student'),
      CharacterRelationshipType.parentChild => ('parent', 'child'),
      CharacterRelationshipType.employerEmployee => ('employer', 'employee'),
      CharacterRelationshipType.guardianWard => ('guardian', 'ward'),
      _ => ('friend', 'friend'),
    };
    editor.sourceRole.text = roles.$1;
    editor.generatedRole.text = roles.$2;
  }

  int _maximumTargetFor(ResourceType type) =>
      ResourceLimits.policyFor(type).nominalCharacters;

  int _targetDivisionsFor(ResourceType type) =>
      (_maximumTargetFor(type) -
          ResourceLimits.minimumGenerationTargetCharacters) ~/
      ResourceLimits.generationTargetStepCharacters;

  /// Smallest accepted target, shared with the Slider.
  int get _minTargetCharacters =>
      ResourceLimits.minimumGenerationTargetCharacters;

  /// Clamps [raw] into the Slider's domain and snaps it to the step grid, so a
  /// typed value is always representable by the Slider and can never carry the
  /// existing capacity/validation contract out of range.
  int _normalizeTargetCharacters(int raw) {
    final min = _minTargetCharacters;
    final max = _maximumTargetFor(_type);
    const step = ResourceLimits.generationTargetStepCharacters;
    final snapped = min + (((raw - min) / step).round()) * step;
    return snapped.clamp(min, max);
  }

  /// Mirrors [_targetCharacters] into the text field.
  ///
  /// Skipped while the field is focused unless [force] is set, so a Slider drag
  /// or a type change never moves the caret while the user is typing.
  void _syncTargetCharactersController({bool force = false}) {
    if (!force && _targetInputFocusNode.hasFocus) return;
    final text = _targetCharacters.toString();
    if (_targetCharactersController.text == text) return;
    _targetCharactersController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _handleTargetInputFocusChange() {
    if (!_targetInputFocusNode.hasFocus && mounted) {
      _commitTargetCharactersInput(_targetCharactersController.text);
    }
  }

  /// Live, non-destructive update while typing: sync the Slider as soon as the
  /// text is a valid in-range integer, but never reformat the text itself.
  void _onTargetCharactersInputChanged(String raw) {
    final parsed = int.tryParse(raw.trim());
    final max = _maximumTargetFor(_type);
    if (parsed != null && parsed >= _minTargetCharacters && parsed <= max) {
      setState(() {
        _targetCharacters = parsed;
        _targetInputError = null;
      });
    } else if (_targetInputError != null) {
      setState(() => _targetInputError = null);
    }
  }

  /// Unified confirm/blur validation.
  ///
  /// A parseable number is clamped + snapped into the domain; a non-numeric or
  /// empty value is rejected and the field is restored to the last valid value,
  /// so an invalid configuration can never reach the generation request.
  void _commitTargetCharactersInput(String raw) {
    if (!mounted) return;
    final parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      setState(() => _targetInputError =
          _l10n(context).resourceTargetCharactersInputInvalid);
      _syncTargetCharactersController(force: true);
      return;
    }
    setState(() {
      _targetCharacters = _normalizeTargetCharacters(parsed);
      _targetInputError = null;
    });
    _syncTargetCharactersController(force: true);
  }

  Widget _buildReferenceContent(
    List<AppSelectItem<ResourceLibraryItem>> existingResourceItems,
    AppLocalizations l10n,
  ) {
    return switch (_referenceMode) {
      AiReferenceMode.paste => AppTextField(
          key: const Key('ai-create-paste-field'),
          controller: _referenceController,
          label: l10n.resourcePasteReferenceLabel,
          hintText: l10n.resourcePasteReferenceHint,
          errorText: _referenceError,
          minLines: 4,
          maxLines: 10,
          onChanged: (_) {
            if (_referenceError != null) {
              setState(() => _referenceError = null);
            }
          },
        ),
      AiReferenceMode.file => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              key: const Key('ai-create-filename-field'),
              controller: _fileNameController,
              label: l10n.resourceFileNameLabel,
              hintText: l10n.resourceFileNameHint,
              errorText: _fileNameError,
              onChanged: (_) {
                if (_fileNameError != null) {
                  setState(() => _fileNameError = null);
                }
              },
            ),
            const SizedBox(height: 8),
            AppTextField(
              key: const Key('ai-create-filecontent-field'),
              controller: _referenceController,
              label: l10n.resourceFileContentLabel,
              hintText: l10n.resourceFileContentHint,
              errorText: _referenceError,
              minLines: 4,
              maxLines: 10,
              onChanged: (_) {
                if (_referenceError != null) {
                  setState(() => _referenceError = null);
                }
              },
            ),
          ],
        ),
      AiReferenceMode.existing => existingResourceItems.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l10n.resourceNoExistingInLibrary,
                style: const TextStyle(color: Colors.grey),
              ),
            )
          : AppSelect<ResourceLibraryItem>(
              key: const Key('ai-create-existing-select'),
              label: l10n.resourceSelectExistingLabel,
              hintText: l10n.resourceSelectExistingHint,
              value: _existingResource,
              items: existingResourceItems,
              errorText: _referenceError,
              onChanged: (val) {
                setState(() {
                  _existingResource = val;
                  _referenceError = null;
                });
              },
            ),
    };
  }
}
