import 'package:flutter/material.dart';

import '../../../../../application/resources/resource_creation_contracts.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../../domain/resources/resource_limits.dart';
import '../../../../core/widgets/ui_foundation.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../widgets/resource_creation_flow.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

enum AiReferenceMode {
  paste,
  file,
  existing,
}

/// AI 智能创建资源页面 [ResourceAiCreatePage]
///
/// 遵循 R02 导航优先架构，将旧版 AlertDialog 弹窗重构为全端标准独立页面：
/// - 资源类型与名称输入 (AppFormSection + AppSelect + AppTextField)
/// - 纯页面内参考资料选择 (粘贴 / 文件 / 已有资源)，消除嵌套弹窗
/// - 深度整合 Material 3 设计规范与 320px 响应式约束
class ResourceAiCreatePage extends StatefulWidget {
  const ResourceAiCreatePage({
    super.key,
    this.initialType = ResourceType.worldview,
    this.resources = const [],
  });

  final ResourceType initialType;
  final List<ResourceLibraryItem> resources;

  @override
  State<ResourceAiCreatePage> createState() => _ResourceAiCreatePageState();
}

class _ResourceAiCreatePageState extends State<ResourceAiCreatePage> {
  final _nameController = TextEditingController();
  final _referenceController = TextEditingController();
  final _fileNameController = TextEditingController();

  late ResourceType _type;
  late int _targetCharacters;
  AiReferenceMode _referenceMode = AiReferenceMode.paste;
  ResourceLibraryItem? _existingResource;
  ResourceLibraryItem? _originWorldview;

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
    if (widget.resources.isNotEmpty) {
      _existingResource = widget.resources.first;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _referenceController.dispose();
    _fileNameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_submitting) return;
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

    if (hasError) return;

    setState(() => _submitting = true);
    Navigator.of(context).pop(
      ResourceStudioCreationDraft(
        type: _type,
        name: name,
        referenceSource: reference,
        targetCharacters: _targetCharacters,
        originWorldviewId: _originWorldview?.id ?? '',
      ),
    );
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
          label: '${res.typeLabel} · ${res.name}',
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
                      });
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
            AppFormSection(
              title: l10n.resourceReferenceSourceTitle,
              description: l10n.resourceReferenceSourceDescription,
              children: [
                SegmentedButton<AiReferenceMode>(
                  key: const Key('ai-create-reference-segmented'),
                  segments: [
                    ButtonSegment(
                      value: AiReferenceMode.paste,
                      icon: const Icon(Icons.content_paste_rounded, size: 18),
                      label: Text(l10n.resourceTabPaste),
                    ),
                    ButtonSegment(
                      value: AiReferenceMode.file,
                      icon: const Icon(Icons.description_outlined, size: 18),
                      label: Text(l10n.resourceTabFile),
                    ),
                    ButtonSegment(
                      value: AiReferenceMode.existing,
                      icon: const Icon(Icons.folder_copy_outlined, size: 18),
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
                    setState(() => _targetCharacters = value.round());
                  },
                ),
                Row(
                  children: [
                    Text(l10n.resourceLengthShort),
                    const Spacer(),
                    Text(l10n.resourceLengthLong),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppPrimaryButton(
              key: const Key('ai-create-submit-button'),
              label: l10n.resourceStartCreateAction,
              icon: Icons.auto_awesome_rounded,
              fullWidth: true,
              isLoading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  int _maximumTargetFor(ResourceType type) =>
      ResourceLimits.policyFor(type).nominalCharacters;

  int _targetDivisionsFor(ResourceType type) =>
      (_maximumTargetFor(type) -
          ResourceLimits.minimumGenerationTargetCharacters) ~/
      ResourceLimits.generationTargetStepCharacters;

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
