import "../core/theme/app_colors.dart";
import 'package:flutter/material.dart';
import '../models/adventure_response.dart';
import '../models/custom_attribute_item.dart';

class AdventureMessageCard extends StatelessWidget {
  final String jsonContent;
  final Brightness brightness;
  final void Function(String option)? onOptionTap;
  final double fontSize;
  final String? defaultCharacterName;

  const AdventureMessageCard({
    super.key,
    required this.jsonContent,
    required this.brightness,
    this.onOptionTap,
    this.fontSize = 14.0,
    this.defaultCharacterName,
  });

  @override
  Widget build(BuildContext context) {
    final response = AdventureResponse.tryParseSplit(jsonContent) ??
        AdventureResponse.tryParse(jsonContent);
    final isDark = brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFD0D0D0) : const Color(0xFF333333);
    const accentColor = AppColors.accent;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (response != null) ...[
            // Scene title
            if (response.scene.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        response.scene,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 1. 叙事正文
            for (final paragraph in response.narrative)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  paragraph,
                  style: TextStyle(
                      fontSize: fontSize, height: 1.8, color: textColor),
                ),
              ),

            // 2. 监测状态（默认展开，绑定角色）
            if (response.customStatus.isNotEmpty) ...[
              _CollapsibleCustomStatus(
                key: PageStorageKey(
                    'custom_status_${response.customStatus.map((s) => '${s.characterName}_${s.name}_${s.value}').join('|')}'),
                statuses: response.customStatus,
                isDark: isDark,
                defaultCharacterName: defaultCharacterName,
              ),
            ],

            // 3. 行动选项
            if (response.options.isNotEmpty) ...[
              _CollapsibleOptions(
                key: PageStorageKey(response.options.join('|')),
                options: response.options,
                isDark: isDark,
                onOptionTap: onOptionTap,
              ),
            ],
          ] else
            Text(
              _formatPlainContent(jsonContent),
              style:
                  TextStyle(fontSize: fontSize, height: 1.8, color: textColor),
            ),
        ],
      ),
    );
  }

  String _formatPlainContent(String content) {
    String text = content;
    if (text.startsWith('```json')) text = text.substring(7);
    if (text.startsWith('```')) text = text.substring(3);
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);
    return text.trim();
  }
}

/// 监测状态折叠组件（默认展开，支持绑定角色分组与非绑定扁平排布）
class _CollapsibleCustomStatus extends StatefulWidget {
  final List<CustomAttributeItem> statuses;
  final bool isDark;
  final String? defaultCharacterName;

  const _CollapsibleCustomStatus({
    super.key,
    required this.statuses,
    required this.isDark,
    this.defaultCharacterName,
  });

  @override
  State<_CollapsibleCustomStatus> createState() =>
      _CollapsibleCustomStatusState();
}

class _CollapsibleCustomStatusState extends State<_CollapsibleCustomStatus> {
  /// 记录被手动折叠的状态块。需求要求"默认展开"，未包含在 set 中的即保持展开。
  static final Set<String> _collapsedKeys = <String>{};

  String get _statusKey => widget.statuses
      .map((s) =>
          '${s.characterName ?? ''}_${s.name}_${s.value}_${s.currentValue}_${s.maxValue}')
      .join('|');

  bool get _expanded => !_collapsedKeys.contains(_statusKey);

  void _toggleExpanded() {
    setState(() {
      if (_expanded) {
        _collapsedKeys.add(_statusKey);
      } else {
        _collapsedKeys.remove(_statusKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.statuses.isEmpty) return const SizedBox.shrink();

    final isDark = widget.isDark;
    final borderCol = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.06);
    final bgCol = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.black.withValues(alpha: 0.03);
    final primaryColor = isDark ? AppColors.darkPrimary : AppColors.primary;

    final defaultChar = (widget.defaultCharacterName != null &&
            widget.defaultCharacterName!.trim().isNotEmpty)
        ? widget.defaultCharacterName!.trim()
        : '角色A';

    if (!_expanded) {
      // 折叠状态条（可点击展开）
      final summaryPreview = widget.statuses.take(2).map((item) {
        final charPrefix = (item.characterName != null &&
                item.characterName!.trim().isNotEmpty)
            ? '${item.characterName}·'
            : '$defaultChar·';
        final icon = item.effectiveIcon;
        final val = item.isNumeric
            ? '${item.effectiveCurrentValue}/${item.effectiveMaxValue}'
            : (item.value.isNotEmpty ? item.value : (item.description ?? ''));
        return '$icon $charPrefix${item.name} $val'.trim();
      }).join('  ·  ');

      return GestureDetector(
        onTap: _toggleExpanded,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(top: 4, bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bgCol,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderCol),
          ),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 14, color: primaryColor),
              const SizedBox(width: 6),
              Text(
                '监测状态',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFFE0E0E0)
                      : const Color(0xFF333333),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${widget.statuses.length}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
              ),
              if (summaryPreview.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summaryPreview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF9E9EB0)
                          : const Color(0xFF6E6E80),
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              const SizedBox(width: 6),
              Text(
                '展开 ▼',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: primaryColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 默认展开状态：绑定角色分组渲染
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgCol,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderCol),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部：监测状态（默认展开）与收起按钮
          GestureDetector(
            onTap: _toggleExpanded,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 14, color: primaryColor),
                const SizedBox(width: 6),
                Text(
                  '监测状态',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? const Color(0xFFE2E2EA)
                        : const Color(0xFF333333),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${widget.statuses.length}项',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: primaryColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '收起 ▲',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _buildCharacterGroupedStatuses(context),
        ],
      ),
    );
  }

  Widget _buildFlatStatuses(List<CustomAttributeItem> items, bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) => _buildStatusBadge(item, isDark)).toList(),
    );
  }

  Widget _buildCharacterGroupedStatuses(BuildContext context) {
    final isDark = widget.isDark;
    final defaultChar = (widget.defaultCharacterName != null &&
            widget.defaultCharacterName!.trim().isNotEmpty)
        ? widget.defaultCharacterName!.trim()
        : '角色A';

    final groups = <String, List<CustomAttributeItem>>{};
    for (final item in widget.statuses) {
      final charName = (item.characterName != null &&
              item.characterName!.trim().isNotEmpty)
          ? item.characterName!.trim()
          : defaultChar;
      groups.putIfAbsent(charName, () => []).add(item);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: groups.entries.map((entry) {
        final charName = entry.key;
        final charItems = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_rounded,
                      size: 13,
                      color: isDark
                          ? const Color(0xFF9E9EB0)
                          : const Color(0xFF666677),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      charName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFFC0C0D0)
                            : const Color(0xFF444455),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _buildFlatStatuses(charItems, isDark),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatusBadge(CustomAttributeItem item, bool isDark) {
    final iconText = item.effectiveIcon;
    final isNumeric = item.isNumeric;
    final itemBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final itemBorder = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.08);

    if (isNumeric) {
      final cur = item.effectiveCurrentValue;
      final max = item.effectiveMaxValue;
      final ratio = item.ratio;

      final isNegativeAttr = item.name.contains('污染') ||
          item.name.contains('侵蚀') ||
          item.name.contains('压力') ||
          item.name.contains('毒') ||
          item.name.contains('变异') ||
          item.name.contains('堕落');

      Color valColor;
      if (isNegativeAttr) {
        if (ratio >= 0.75) {
          valColor = AppColors.error;
        } else if (ratio >= 0.45) {
          valColor = AppColors.warning;
        } else {
          valColor = isDark ? AppColors.darkPrimary : AppColors.primary;
        }
      } else {
        if (ratio <= 0.25) {
          valColor = AppColors.error;
        } else if (ratio <= 0.5) {
          valColor = AppColors.warning;
        } else {
          valColor = isDark ? AppColors.darkPrimary : AppColors.primary;
        }
      }

      final badge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: itemBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: itemBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(iconText, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF333333),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$cur/$max',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: valColor,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 44,
              height: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio,
                  backgroundColor: valColor.withValues(alpha: 0.2),
                  color: valColor,
                ),
              ),
            ),
          ],
        ),
      );

      if (item.description != null && item.description!.trim().isNotEmpty) {
        return Tooltip(
          message: item.description!.trim(),
          child: badge,
        );
      }
      return badge;
    }

    // 非数值（阶段/描述状态）
    final dispValue =
        item.value.isNotEmpty ? item.value : (item.description ?? '');
    final primaryColor = isDark ? AppColors.darkPrimary : AppColors.primary;

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: itemBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: itemBorder),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: WrapAlignment.start,
        children: [
          Text(iconText, style: const TextStyle(fontSize: 13)),
          Text(
            item.name,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFE0E0E0) : const Color(0xFF333333),
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (dispValue.isNotEmpty) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                dispValue,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ],
      ),
    );

    if (item.description != null &&
        item.description!.trim().isNotEmpty &&
        dispValue != item.description!.trim()) {
      return Tooltip(
        message: item.description!.trim(),
        child: badge,
      );
    }
    return badge;
  }
}

class _CollapsibleOptions extends StatefulWidget {
  final List<String> options;
  final bool isDark;
  final void Function(String)? onOptionTap;

  const _CollapsibleOptions({
    super.key,
    required this.options,
    required this.isDark,
    this.onOptionTap,
  });

  @override
  State<_CollapsibleOptions> createState() => _CollapsibleOptionsState();
}

class _CollapsibleOptionsState extends State<_CollapsibleOptions> {
  static final Set<String> _collapsedKeys = <String>{};

  String get _optionsKey => widget.options.join('|');

  bool get _expanded => !_collapsedKeys.contains(_optionsKey);

  void _toggleExpanded() {
    setState(() {
      if (_expanded) {
        _collapsedKeys.add(_optionsKey);
      } else {
        _collapsedKeys.remove(_optionsKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.accent;
    final isDark = widget.isDark;

    if (!_expanded) {
      return GestureDetector(
        onTap: _toggleExpanded,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.touch_app, size: 13, color: accent),
            const SizedBox(width: 4),
            Text('选项 (${widget.options.length} 个选项)',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500, color: accent)),
            const Spacer(),
            Text('展开 ▼',
                style: TextStyle(
                    fontSize: 10, color: accent.withValues(alpha: 0.6))),
          ]),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: _toggleExpanded,
          child: Row(children: [
            Text('选项 (${widget.options.length} 个选项)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('收起 ▲',
                style: TextStyle(
                    fontSize: 10, color: accent.withValues(alpha: 0.6))),
          ]),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: widget.options
              .map((opt) => GestureDetector(
                    onTap: () {
                      final optCopy = opt;
                      // Keep panel open after selection; user can collapse manually.
                      Future.microtask(() => widget.onOptionTap?.call(optCopy));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: accent.withValues(alpha: 0.25)),
                      ),
                      child: Text(opt,
                          style: const TextStyle(
                              fontSize: 13,
                              color: accent,
                              fontWeight: FontWeight.w500)),
                    ),
                  ))
              .toList(),
        ),
      ]),
    );
  }
}
