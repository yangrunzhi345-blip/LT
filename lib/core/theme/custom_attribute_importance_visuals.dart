import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../models/custom_attribute_item.dart';
import 'app_colors.dart';

/// Presentation-only visuals for [CustomAttributeImportance].
///
/// The domain enum in `models/custom_attribute_item.dart` stays free of
/// Flutter material types; UI layers opt into these colors/icons explicitly.
extension CustomAttributeImportanceVisuals on CustomAttributeImportance {
  /// 重要度对应的高亮颜色
  Color get color => switch (this) {
        CustomAttributeImportance.reference => const Color(0xFF8A9099),
        CustomAttributeImportance.important => AppColors.teal,
        CustomAttributeImportance.veryImportant => const Color(0xFFE67E22),
        CustomAttributeImportance.critical => const Color(0xFFE74C3C),
      };

  /// 重要度前缀图标（SVG asset 名称）
  String get icon => switch (this) {
        CustomAttributeImportance.reference => 'info',
        CustomAttributeImportance.important => 'bookmark',
        CustomAttributeImportance.veryImportant => 'star',
        CustomAttributeImportance.critical => 'warning',
      };

  /// 本地化重要度展示文案
  String localizedLabel(AppLocalizations? l10n) {
    if (l10n == null) return label;
    return switch (this) {
      CustomAttributeImportance.reference =>
        l10n.customAttributeImportanceReference,
      CustomAttributeImportance.important =>
        l10n.customAttributeImportanceImportant,
      CustomAttributeImportance.veryImportant =>
        l10n.customAttributeImportanceVeryImportant,
      CustomAttributeImportance.critical =>
        l10n.customAttributeImportanceCritical,
    };
  }
}
