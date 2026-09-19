import 'package:flutter/material.dart';

import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../core/widgets/ui_foundation.dart';
import '../widgets/resource_creation_flow.dart';

/// 手动空白创建资源页面 [ResourceManualCreatePage]
///
/// 遵循 R02 导航优先架构，替代原有的 AlertDialog 弹窗表单。
class ResourceManualCreatePage extends StatefulWidget {
  const ResourceManualCreatePage({
    super.key,
    this.initialType = ResourceType.worldview,
  });

  final ResourceType initialType;

  @override
  State<ResourceManualCreatePage> createState() =>
      _ResourceManualCreatePageState();
}

class _ResourceManualCreatePageState extends State<ResourceManualCreatePage> {
  final _nameController = TextEditingController();
  final _summaryController = TextEditingController();
  late ResourceType _type;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _summaryController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '请输入资源名称');
      return;
    }

    Navigator.of(context).pop(
      ManualResourceDraft(
        type: _type,
        name: name,
        summary: _summaryController.text.trim(),
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

    return AppPageScaffold(
      title: '手动创建资源',
      maxWidth: 640,
      scrollable: true,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: '基本信息',
              description: '填写资源的类型、名称与简要介绍，创建后即可在工作室中自由编排正文',
              children: [
                AppSelect<ResourceType>(
                  key: const Key('manual-create-type-select'),
                  label: '资源类型',
                  value: _type,
                  items: typeItems,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _type = val);
                    }
                  },
                ),
                AppTextField(
                  key: const Key('manual-create-name-field'),
                  controller: _nameController,
                  label: '名称',
                  hintText: '输入清晰明确的名称',
                  errorText: _nameError,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_nameError != null) {
                      setState(() => _nameError = null);
                    }
                  },
                ),
                AppTextField(
                  key: const Key('manual-create-summary-field'),
                  controller: _summaryController,
                  label: '简介（可选）',
                  hintText: '简要介绍该资源的定位与背景设定',
                  minLines: 3,
                  maxLines: 6,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppPrimaryButton(
              key: const Key('manual-create-submit-button'),
              label: '创建',
              icon: Icons.check_rounded,
              fullWidth: true,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
