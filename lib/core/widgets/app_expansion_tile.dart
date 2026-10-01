import 'package:flutter/material.dart';

import 'app_svg_icon.dart';

/// Standard expansion behavior with the workbench's SVG state indicator.
class AppExpansionTile extends StatefulWidget {
  const AppExpansionTile(
      {super.key,
      required this.title,
      required this.children,
      this.subtitle,
      this.initiallyExpanded = false,
      this.childrenPadding,
      this.shape,
      this.collapsedShape});

  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;
  final EdgeInsetsGeometry? childrenPadding;
  final ShapeBorder? shape;
  final ShapeBorder? collapsedShape;

  @override
  State<AppExpansionTile> createState() => _AppExpansionTileState();
}

class _AppExpansionTileState extends State<AppExpansionTile> {
  late bool _isExpanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        title: widget.title,
        subtitle: widget.subtitle,
        initiallyExpanded: widget.initiallyExpanded,
        childrenPadding: widget.childrenPadding,
        shape: widget.shape,
        collapsedShape: widget.collapsedShape,
        onExpansionChanged: (expanded) =>
            setState(() => _isExpanded = expanded),
        trailing: AnimatedRotation(
          turns: _isExpanded ? .5 : 0,
          duration: const Duration(milliseconds: 180),
          child: const AppSvgIcon('down'),
        ),
        children: widget.children,
      );
}
