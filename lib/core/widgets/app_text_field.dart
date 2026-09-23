import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/generated/app_localizations.dart';
import '../theme/app_spacing.dart';

/// 统一语义化文本输入框组件
/// 严格遵循 Material 3 设计令牌，自动适应浅色/暗色及主色种子
class AppTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool isPassword;
  final bool readOnly;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final VoidCallback? onTap;

  const AppTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.isPassword = false,
    this.readOnly = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.focusNode,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.onTap,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured;

  @override
  void initState() {
    super.initState();
    _obscured = widget.isPassword;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveEnabled = widget.enabled;

    Widget? effectiveSuffix = widget.suffixIcon;
    if (widget.isPassword) {
      final l10n = AppLocalizations.of(context);
      effectiveSuffix = IconButton(
        icon: Icon(
          _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
          color: effectiveEnabled
              ? colorScheme.onSurfaceVariant
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.38),
        ),
        tooltip: _obscured
            ? (l10n?.showPassword ?? 'Show password')
            : (l10n?.hidePassword ?? 'Hide password'),
        onPressed: effectiveEnabled
            ? () => setState(() => _obscured = !_obscured)
            : null,
      );
    }

    final field = TextFormField(
      controller: widget.controller,
      initialValue: widget.initialValue,
      enabled: effectiveEnabled,
      focusNode: widget.focusNode,
      textInputAction: widget.textInputAction,
      obscureText: _obscured,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      maxLines: widget.isPassword ? 1 : widget.maxLines,
      minLines: widget.minLines,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      onTap: effectiveEnabled ? widget.onTap : null,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: effectiveEnabled
            ? colorScheme.onSurface
            : colorScheme.onSurface.withValues(alpha: 0.38),
      ),
      decoration: InputDecoration(
        hintText: widget.hintText,
        helperText: widget.helperText,
        errorText: widget.errorText,
        prefixIcon: widget.prefixIcon,
        suffixIcon: effectiveSuffix,
        isDense: true,
        filled: true,
        fillColor: effectiveEnabled
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.error,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 1.5,
          ),
        ),
      ),
    );

    if (widget.label != null && widget.label!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label!,
            style: theme.textTheme.titleSmall?.copyWith(
              color: effectiveEnabled
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withValues(alpha: 0.45),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          field,
        ],
      );
    }

    return field;
  }
}
