import 'app_dropdown.dart';

export 'app_dropdown.dart';

class NarrAItorDropdownOption<T> extends AppDropdownOption<T> {
  const NarrAItorDropdownOption({
    required super.value,
    required super.label,
    super.leading,
    super.icon,
    super.subtitle,
    super.actionTooltip,
    super.onAction,
    super.enabled = true,
    super.dividerBefore = false,
    super.customWidget,
  });
}

class NarrAItorDropdown<T> extends AppDropdown<T> {
  const NarrAItorDropdown({
    super.key,
    required super.value,
    required super.options,
    required super.onChanged,
    super.label,
    super.hintText,
    super.errorText,
    super.enabled = true,
    super.expanded = true,
    super.prefix,
    super.variant,
    super.direction,
    super.triggerHeight,
    super.triggerPadding,
    super.menuWidth,
    super.menuMaxHeight,
    super.showArrow = true,
    super.tooltip,
    super.semanticLabel,
    super.selectedBuilder,
    super.optionBuilder,
  });
}

class NarrAItorMultiSelectDropdown<T> extends AppMultiSelectDropdown<T> {
  const NarrAItorMultiSelectDropdown({
    super.key,
    required super.values,
    required super.options,
    required super.onChanged,
    super.label,
    super.hintText,
    super.enabled = true,
    super.expanded = true,
    super.prefix,
    super.direction,
    super.triggerHeight,
    super.triggerPadding,
    super.showArrow = true,
    super.menuWidth,
    super.tooltip,
    super.semanticLabel,
    super.emptyText,
    super.selectedBuilder,
  });
}
