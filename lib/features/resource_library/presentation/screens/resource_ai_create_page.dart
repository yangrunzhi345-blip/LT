import 'package:flutter/material.dart';

import '../../../../../application/resources/resource_creation_contracts.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../../domain/resources/resource_limits.dart';
import '../../../../core/widgets/ui_foundation.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../widgets/resource_creation_flow.dart';

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
    final name = _nameController.text.trim();
    bool hasError = false;

    if (name.isEmpty) {
      setState(() => _nameError = '请输入资源名称');
      hasError = true;
    }

    ReferenceSource reference;
    switch (_referenceMode) {
      case AiReferenceMode.paste:
        final text = _referenceController.text.trim();
        if (text.isEmpty) {
          setState(() => _referenceError = '请输入或粘贴参考资料正文');
          hasError = true;
        }
        reference = ReferenceSource.text(text, label: '粘贴内容');

      case AiReferenceMode.file:
        final fileName = _fileNameController.text.trim();
        final text = _referenceController.text.trim();
        if (fileName.isEmpty) {
          setState(() => _fileNameError = '请输入文件名');
          hasError = true;
        }
        if (text.isEmpty) {
          setState(() => _referenceError = '请输入文件内容');
          hasError = true;
        }
        reference = ReferenceSource.file(text, fileName: fileName);

      case AiReferenceMode.existing:
        final existing = _existingResource;
        if (existing == null || existing.id.isEmpty) {
          setState(() => _referenceError = '请选择一个已有的资源作为参考');
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typeItems = [
      for (final type in ResourceType.values)
        AppSelectItem<ResourceType>(
          value: type,
          label: resourceTypeLabel(type),
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

    return AppPageScaffold(
      title: 'AI 智能创建资源',
      maxWidth: 640,
      scrollable: true,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: '基本信息',
              description: '定义即将生成的资源载体类型与标题',
              children: [
                AppSelect<ResourceType>(
                  key: const Key('ai-create-type-select'),
                  label: '资源类型',
                  value: _type,
                  items: typeItems,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _type = val;
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
                  label: '名称',
                  hintText: '输入将要生成的设定或角色名称',
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
            AppFormSection(
              title: '参考资料来源',
              description: '提供世界观背景、小说设定或关联资源，AI 将提取精髓并推演章节架构',
              children: [
                SegmentedButton<AiReferenceMode>(
                  key: const Key('ai-create-reference-segmented'),
                  segments: const [
                    ButtonSegment(
                      value: AiReferenceMode.paste,
                      icon: Icon(Icons.content_paste_rounded, size: 18),
                      label: Text('粘贴'),
                    ),
                    ButtonSegment(
                      value: AiReferenceMode.file,
                      icon: Icon(Icons.description_outlined, size: 18),
                      label: Text('文件'),
                    ),
                    ButtonSegment(
                      value: AiReferenceMode.existing,
                      icon: Icon(Icons.folder_copy_outlined, size: 18),
                      label: Text('已有资源'),
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
                _buildReferenceContent(existingResourceItems),
              ],
            ),
            const SizedBox(height: 12),
            AppFormSection(
              title: '生成长度',
              description: '控制 AI 生成资源正文的大致目标字数',
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('目标字数')),
                    Text(
                      '$_targetCharacters 字',
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
                  label: '$_targetCharacters 字',
                  onChanged: (value) {
                    setState(() => _targetCharacters = value.round());
                  },
                ),
                const Row(
                  children: [
                    Text('短篇'),
                    Spacer(),
                    Text('长篇'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppPrimaryButton(
              key: const Key('ai-create-submit-button'),
              label: '开始创建',
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
  ) {
    return switch (_referenceMode) {
      AiReferenceMode.paste => AppTextField(
          key: const Key('ai-create-paste-field'),
          controller: _referenceController,
          label: '粘贴参考内容',
          hintText: '输入或粘贴小说大纲、设定集草稿或背景描述...',
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
              label: '文件名',
              hintText: '例如: world_notes.md',
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
              label: '文件文本内容',
              hintText: '粘贴或输入文件内的原始文本...',
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
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '资料库中暂无可关联的已就绪资源，请切换至「粘贴」或「文件」输入。',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : AppSelect<ResourceLibraryItem>(
              key: const Key('ai-create-existing-select'),
              label: '选择已有资源',
              hintText: '点击选取参考的既有资源',
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
