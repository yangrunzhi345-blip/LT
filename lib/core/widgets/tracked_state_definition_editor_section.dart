import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/custom_attribute_item.dart';
import '../../models/tracked_state_definition.dart';
import '../../models/typed_runtime_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/custom_attribute_importance_visuals.dart';
import 'app_dropdown.dart';
import 'app_svg_icon.dart';

/// Shared editor for [TrackedStateDefinition] on characters, NPCs and
/// worldviews.
///
/// One editor for every resource type: no resource grows a second monitoring
/// model. The editor edits **definitions only** — there is no current-value
/// field, which is the structural guarantee that a resource never stores
/// runtime state.
///
/// [framed] controls the outer presentation. Resource editors embed it as a
/// framed panel; the workbench management page sets `framed: false` and lets
/// its own section header own the hierarchy, so the editor never becomes a
/// card nested inside another card.
class TrackedStateDefinitionEditorSection extends StatefulWidget {
  final List<TrackedStateDefinition> initialItems;
  final ValueChanged<List<TrackedStateDefinition>> onChanged;
  final String? title;
  final String? subtitle;
  final bool framed;

  const TrackedStateDefinitionEditorSection({
    super.key,
    required this.initialItems,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.framed = true,
  });

  @override
  State<TrackedStateDefinitionEditorSection> createState() =>
      _TrackedStateDefinitionEditorSectionState();
}

class _TrackedStateDefinitionEntry {
  String id;
  final TextEditingController nameCtrl;
  final TextEditingController ruleCtrl;
  final TextEditingController minCtrl;
  final TextEditingController maxCtrl;
  final TextEditingController enumCtrl;
  RuntimeStateValueKind kind;
  CustomAttributeImportance importance;

  _TrackedStateDefinitionEntry({
    required this.id,
    required String name,
    required String rule,
    required this.kind,
    required this.importance,
    num? minimum,
    num? maximum,
    Set<String> enumValues = const {},
  })  : nameCtrl = TextEditingController(text: name),
        ruleCtrl = TextEditingController(text: rule),
        minCtrl = TextEditingController(
            text: minimum == null ? '' : _formatNumber(minimum)),
        maxCtrl = TextEditingController(
            text: maximum == null ? '' : _formatNumber(maximum)),
        enumCtrl = TextEditingController(text: enumValues.join('、'));

  void dispose() {
    nameCtrl.dispose();
    ruleCtrl.dispose();
    minCtrl.dispose();
    maxCtrl.dispose();
    enumCtrl.dispose();
  }

  TrackedStateDefinition toDefinition() {
    final name = nameCtrl.text.trim();
    final resolvedId =
        id.trim().isNotEmpty ? id.trim() : TrackedStateDefinition.slugify(name);
    final isNumeric = kind == RuntimeStateValueKind.integer ||
        kind == RuntimeStateValueKind.number;
    final enumValues = enumCtrl.text
        .split(RegExp(r'[、,，;；]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    return TrackedStateDefinition(
      id: resolvedId,
      name: name,
      valueKind: kind,
      description: ruleCtrl.text.trim(),
      importance: importance,
      minimum: isNumeric ? num.tryParse(minCtrl.text.trim()) : null,
      maximum: isNumeric ? num.tryParse(maxCtrl.text.trim()) : null,
      enumValues:
          kind == RuntimeStateValueKind.enumValue ? enumValues : const {},
    );
  }

  static String _formatNumber(num value) => value == value.truncate()
      ? value.truncate().toString()
      : value.toString();
}

class _TrackedStateDefinitionEditorSectionState
    extends State<TrackedStateDefinitionEditorSection> {
  final List<_TrackedStateDefinitionEntry> _entries = [];
  final List<_TrackedStateDefinitionEntry> _pendingDisposal = [];

  @override
  void initState() {
    super.initState();
    for (final item in widget.initialItems) {
      _addFromDefinition(item);
    }
  }

  void _addFromDefinition(TrackedStateDefinition item) {
    final entry = _TrackedStateDefinitionEntry(
      id: item.id,
      name: item.name,
      rule: item.description,
      kind: item.valueKind,
      importance: item.importance,
      minimum: item.minimum,
      maximum: item.maximum,
      enumValues: item.enumValues,
    );
    _bindListeners(entry);
    _entries.add(entry);
  }

  void _bindListeners(_TrackedStateDefinitionEntry entry) {
    for (final controller in [
      entry.nameCtrl,
      entry.ruleCtrl,
      entry.minCtrl,
      entry.maxCtrl,
      entry.enumCtrl,
    ]) {
      controller.addListener(_notifyChanged);
    }
  }

  void _notifyChanged() =>
      widget.onChanged(_entries.map((e) => e.toDefinition()).toList());

  void _addNew() {
    setState(() {
      final entry = _TrackedStateDefinitionEntry(
        id: '',
        name: '',
        rule: '',
        kind: RuntimeStateValueKind.integer,
        importance: CustomAttributeImportance.reference,
      );
      _bindListeners(entry);
      _entries.add(entry);
    });
    _notifyChanged();
  }

  void _remove(int index) {
    if (index < 0 || index >= _entries.length) return;
    final removed = _entries.removeAt(index);
    for (final controller in [
      removed.nameCtrl,
      removed.ruleCtrl,
      removed.minCtrl,
      removed.maxCtrl,
      removed.enumCtrl,
    ]) {
      controller.removeListener(_notifyChanged);
    }
    _pendingDisposal.add(removed);
    setState(() {});
    _notifyChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final entry in _pendingDisposal) {
        entry.dispose();
      }
      _pendingDisposal.clear();
    });
  }

  void _setKind(int index, RuntimeStateValueKind kind) {
    setState(() => _entries[index].kind = kind);
    _notifyChanged();
  }

  void _setImportance(int index, CustomAttributeImportance importance) {
    setState(() => _entries[index].importance = importance);
    _notifyChanged();
  }

  @override
  void dispose() {
    for (final entry in [..._entries, ..._pendingDisposal]) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(context, l10n),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.md),
        if (_entries.isEmpty)
          _buildEmptyState(context, l10n)
        else
          ..._entries
              .asMap()
              .entries
              .map((entry) => _buildCard(context, entry.key, entry.value)),
      ],
    );

    if (!widget.framed) return content;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: content,
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations? l10n) {
    final scheme = Theme.of(context).colorScheme;
    final title =
        widget.title ?? l10n?.trackedStateSectionTitle ?? 'Monitored Fields';
    final subtitle = widget.subtitle ?? l10n?.trackedStateSectionSubtitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: AppSvgIcon('tune', size: 18, color: AppColors.teal),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        FilledButton.tonal(
          onPressed: _addNew,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          child: Text(
            l10n?.trackedStateAddAction ?? 'Add monitor',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, AppLocalizations? l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n?.trackedStateNoDefinitions ?? 'No monitored fields',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n?.trackedStateNoDefinitionsHint ?? '',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String? label,
    String? hint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color color, {double width = 1}) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: border(scheme.outlineVariant),
      enabledBorder: border(scheme.outlineVariant),
      focusedBorder: border(scheme.primary, width: 1.4),
    );
  }

  Widget _buildCard(
      BuildContext context, int index, _TrackedStateDefinitionEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final isNumeric = entry.kind == RuntimeStateValueKind.integer ||
        entry.kind == RuntimeStateValueKind.number;

    return Container(
      key: ValueKey(entry.id.isEmpty ? 'new-$index' : entry.id),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: entry.nameCtrl,
                  decoration: _inputDecoration(
                    context,
                    label: l10n?.trackedStateNameLabel ?? 'Name *',
                    hint: l10n?.trackedStateNameHint ?? '',
                  ),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 4,
                child: AppDropdown<RuntimeStateValueKind>.compact(
                  value: entry.kind,
                  direction: AppDropdownDirection.down,
                  options: [
                    for (final kind in RuntimeStateValueKind.values)
                      AppDropdownOption(
                        value: kind,
                        label: _kindLabel(kind, l10n),
                      ),
                  ],
                  selectedBuilder: (value) => Text(
                    _kindLabel(value ?? entry.kind, l10n),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (value) {
                    if (value != null) _setKind(index, value);
                  },
                ),
              ),
              IconButton(
                icon: const AppSvgIcon('close', size: 18),
                color: scheme.onSurfaceVariant,
                tooltip: l10n?.trackedStateDeleteTitle ?? 'Delete',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: () => _remove(index),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: entry.ruleCtrl,
            maxLines: 2,
            minLines: 1,
            decoration: _inputDecoration(
              context,
              label: l10n?.trackedStateRuleLabel ?? 'Detection rule',
              hint: l10n?.trackedStateRuleHint ?? '',
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 150,
                child: AppDropdown<CustomAttributeImportance>.compact(
                  value: entry.importance,
                  direction: AppDropdownDirection.down,
                  options: [
                    for (final importance in CustomAttributeImportance.values)
                      AppDropdownOption(
                        value: importance,
                        label: importance.localizedLabel(l10n),
                        icon: importance.icon,
                      ),
                  ],
                  selectedBuilder: (value) {
                    final importance =
                        value ?? CustomAttributeImportance.reference;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppSvgIcon(importance.icon,
                            size: 14, color: importance.color),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            importance.localizedLabel(l10n),
                            style: TextStyle(
                                fontSize: 12, color: importance.color),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                  onChanged: (value) {
                    if (value != null) _setImportance(index, value);
                  },
                ),
              ),
              if (isNumeric) ...[
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: entry.minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                      context,
                      label: l10n?.trackedStateMinLabel ?? 'Min',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: entry.maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDecoration(
                      context,
                      label: l10n?.trackedStateMaxLabel ?? 'Max',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              if (entry.kind == RuntimeStateValueKind.enumValue)
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: entry.enumCtrl,
                    decoration: _inputDecoration(
                      context,
                      label: l10n?.trackedStateEnumLabel ?? 'Allowed values',
                      hint: l10n?.trackedStateEnumHint ?? '',
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _kindLabel(RuntimeStateValueKind kind, AppLocalizations? l10n) =>
      switch (kind) {
        RuntimeStateValueKind.number =>
          l10n?.trackedStateKindNumber ?? 'Number',
        RuntimeStateValueKind.integer =>
          l10n?.trackedStateKindInteger ?? 'Integer',
        RuntimeStateValueKind.text => l10n?.trackedStateKindText ?? 'Text',
        RuntimeStateValueKind.boolean =>
          l10n?.trackedStateKindBoolean ?? 'Boolean',
        RuntimeStateValueKind.enumValue => l10n?.trackedStateKindEnum ?? 'Enum',
      };
}
