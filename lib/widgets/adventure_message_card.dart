import "../core/theme/app_colors.dart";
import 'package:flutter/material.dart';
import '../models/adventure_response.dart';

class AdventureMessageCard extends StatelessWidget {
  final String jsonContent;
  final Brightness brightness;
  final void Function(String option)? onOptionTap;
  final double fontSize;

  const AdventureMessageCard({
    super.key,
    required this.jsonContent,
    required this.brightness,
    this.onOptionTap,
    this.fontSize = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    final response = AdventureResponse.tryParseSplit(jsonContent) ??
        AdventureResponse.tryParse(jsonContent);
    final isDark = brightness == Brightness.dark;
    final textColor =
        isDark ? const Color(0xFFD0D0D0) : const Color(0xFF333333);
    final mutedColor =
        isDark ? const Color(0xFF8888AA) : const Color(0xFF888888);
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

            // State bar inline
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  _statBadge('HP', response.hp, response.maxHp,
                      const Color(0xFFE53935), mutedColor),
                  const SizedBox(width: 14),
                  _statBadge('EN', response.energy, response.maxEnergy,
                      AppColors.primary, mutedColor),
                  const SizedBox(width: 14),
                  _statBadge('G', response.gold, null, const Color(0xFFF9A825),
                      mutedColor),
                ],
              ),
            ),

            // Inventory
            if (response.inventory.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: response.inventory
                      .map((item) => Text(item,
                          style: TextStyle(fontSize: 12, color: mutedColor)))
                      .toList(),
                ),
              ),
            ],

            // Separator
            Container(
              height: 1,
              margin: const EdgeInsets.only(bottom: 12),
              color: isDark ? const Color(0xFF2A2A44) : const Color(0xFFE0E0F0),
            ),

            // Narrative
            for (final paragraph in response.narrative)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  paragraph,
                  style: TextStyle(
                      fontSize: fontSize, height: 1.8, color: textColor),
                ),
              ),

            // Options at bottom — collapsible
            if (response.options.isNotEmpty) ...[
              _CollapsibleOptions(
                key: ValueKey(response.options),
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

  Widget _statBadge(
      String icon, int value, int? max, Color color, Color muted) {
    final text = max != null ? '$value/$max' : '$value';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
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

class _CollapsibleOptions extends StatefulWidget {
  final List<String> options;
  final bool isDark;
  final void Function(String)? onOptionTap;

  const _CollapsibleOptions({
    Key? key,
    required this.options,
    required this.isDark,
    this.onOptionTap,
  }) : super(key: key);

  @override
  State<_CollapsibleOptions> createState() => _CollapsibleOptionsState();
}

class _CollapsibleOptionsState extends State<_CollapsibleOptions> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.accent;
    final isDark = widget.isDark;

    if (!_expanded) {
      return GestureDetector(
        onTap: () => setState(() => _expanded = true),
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
            Text('${widget.options.length} 个选项',
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
          onTap: () => setState(() => _expanded = false),
          child: Row(children: [
            const Text('行动选项',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
                      setState(() => _expanded = false);
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
