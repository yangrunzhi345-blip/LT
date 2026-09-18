import 'package:flutter/material.dart';

import '../../../../../application/resources/resource_creation_contracts.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../../domain/models/resource_library_view_state.dart';

enum ResourceCreationChoice { ai, manual }

Future<ResourceCreationChoice?> showResourceCreationChoices(
  BuildContext context,
) {
  return showModalBottomSheet<ResourceCreationChoice>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('新建资源', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.auto_awesome_rounded),
              title: const Text('AI 创建'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(
                sheetContext,
                ResourceCreationChoice.ai,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('手动创建'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(
                sheetContext,
                ResourceCreationChoice.manual,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

final class ManualResourceDraft {
  const ManualResourceDraft({
    required this.type,
    required this.name,
    required this.summary,
  });

  final ResourceType type;
  final String name;
  final String summary;
}

Future<ManualResourceDraft?> showManualResourceDialog(BuildContext context) {
  return showDialog<ManualResourceDraft>(
    context: context,
    builder: (_) => const _ManualResourceDialog(),
  );
}

Future<ResourceStudioCreationDraft?> showAiResourceDialog(
  BuildContext context, {
  required List<ResourceLibraryItem> resources,
}) {
  return showDialog<ResourceStudioCreationDraft>(
    context: context,
    builder: (_) => _AiResourceDialog(resources: resources),
  );
}

String resourceTypeLabel(ResourceType type) => switch (type) {
      ResourceType.worldview => '世界观',
      ResourceType.character => '角色',
      ResourceType.npc => 'NPC',
    };

final class _ManualResourceDialog extends StatefulWidget {
  const _ManualResourceDialog();

  @override
  State<_ManualResourceDialog> createState() => _ManualResourceDialogState();
}

final class _ManualResourceDialogState extends State<_ManualResourceDialog> {
  final _nameController = TextEditingController();
  final _summaryController = TextEditingController();
  ResourceType _type = ResourceType.worldview;

  @override
  void dispose() {
    _nameController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('手动创建'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<ResourceType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: '资源类型'),
                items: [
                  for (final type in ResourceType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(resourceTypeLabel(type)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _summaryController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '简介（可选）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = _nameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(
                context,
                ManualResourceDraft(
                  type: _type,
                  name: name,
                  summary: _summaryController.text.trim(),
                ),
              );
            },
            child: const Text('创建'),
          ),
        ],
      );
}

enum _ReferenceChoice { paste, file, existing }

final class _AiResourceDialog extends StatefulWidget {
  const _AiResourceDialog({required this.resources});

  final List<ResourceLibraryItem> resources;

  @override
  State<_AiResourceDialog> createState() => _AiResourceDialogState();
}

final class _AiResourceDialogState extends State<_AiResourceDialog> {
  final _nameController = TextEditingController();
  final _referenceController = TextEditingController();
  ResourceType _type = ResourceType.worldview;
  _ReferenceChoice _referenceChoice = _ReferenceChoice.paste;
  ResourceLibraryItem? _existingResource;
  String _fileName = '';

  @override
  void dispose() {
    _nameController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('AI 创建'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<ResourceType>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: '资源类型'),
                  items: [
                    for (final type in ResourceType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(resourceTypeLabel(type)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _type = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 16),
                Text('参考资料', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<_ReferenceChoice>(
                  segments: const [
                    ButtonSegment(
                      value: _ReferenceChoice.paste,
                      icon: Icon(Icons.content_paste_rounded),
                      label: Text('粘贴'),
                    ),
                    ButtonSegment(
                      value: _ReferenceChoice.file,
                      icon: Icon(Icons.description_outlined),
                      label: Text('文件'),
                    ),
                    ButtonSegment(
                      value: _ReferenceChoice.existing,
                      icon: Icon(Icons.folder_copy_outlined),
                      label: Text('已有资源'),
                    ),
                  ],
                  selected: <_ReferenceChoice>{_referenceChoice},
                  onSelectionChanged: (selection) {
                    setState(() => _referenceChoice = selection.single);
                  },
                ),
                const SizedBox(height: 12),
                _buildReferenceInput(context),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('开始创建'),
          ),
        ],
      );

  Widget _buildReferenceInput(BuildContext context) {
    return switch (_referenceChoice) {
      _ReferenceChoice.paste => TextField(
          controller: _referenceController,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: '粘贴参考内容',
            alignLabelWithHint: true,
          ),
        ),
      _ReferenceChoice.file => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onChanged: (value) => _fileName = value,
              decoration: const InputDecoration(labelText: '文件名'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _referenceController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '文件内容',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      _ReferenceChoice.existing => DropdownButtonFormField<ResourceLibraryItem>(
          initialValue: _existingResource,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '选择已有资源'),
          items: [
            for (final resource in widget.resources)
              DropdownMenuItem(
                value: resource,
                child: Text(
                  '${resource.typeLabel} · ${resource.name}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (value) => setState(() => _existingResource = value),
        ),
    };
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final reference = switch (_referenceChoice) {
      _ReferenceChoice.paste => ReferenceSource.text(
          _referenceController.text.trim(),
          label: '粘贴内容',
        ),
      _ReferenceChoice.file => ReferenceSource.file(
          _referenceController.text,
          fileName: _fileName,
        ),
      _ReferenceChoice.existing => ReferenceSource.existingResource(
          _existingResource?.id ?? '',
          label: _existingResource?.name ?? '',
        ),
    };
    final isValid = switch (_referenceChoice) {
      _ReferenceChoice.paste => reference.hasBody,
      _ReferenceChoice.file => _fileName.isNotEmpty && reference.hasBody,
      _ReferenceChoice.existing =>
        reference.existingResourceId.trim().isNotEmpty,
    };
    if (!isValid) return;
    Navigator.pop(
      context,
      ResourceStudioCreationDraft(
        type: _type,
        name: name,
        referenceSource: reference,
      ),
    );
  }
}
