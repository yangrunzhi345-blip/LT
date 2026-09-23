import 'package:flutter/material.dart';

import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../core/widgets/ui_foundation.dart';
import '../widgets/resource_creation_flow.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

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
    final l10n = _l10n(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = l10n.resourceInputNameError);
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
    final l10n = _l10n(context);
    final typeItems = [
      for (final type in ResourceType.values)
        AppSelectItem<ResourceType>(
          value: type,
          label: resourceTypeLabel(type, l10n),
        ),
    ];

    return AppPageScaffold(
      title: l10n.resourceManualCreateTitle,
      maxWidth: 640,
      scrollable: true,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: l10n.resourceBasicInfoTitle,
              description: l10n.resourceManualBasicInfoDescription,
              children: [
                AppSelect<ResourceType>(
                  key: const Key('manual-create-type-select'),
                  label: l10n.resourceTypeSectionTitle,
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
                  label: l10n.resourceNameLabel,
                  hintText: l10n.resourceManualNameHint,
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
                  label: l10n.resourceSummaryOptionalLabel,
                  hintText: l10n.resourceManualSummaryHint,
                  minLines: 3,
                  maxLines: 6,
                ),
              ],
            ),
            const SizedBox(height: 16),
            AppPrimaryButton(
              key: const Key('manual-create-submit-button'),
              label: l10n.resourceCreateAction,
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
