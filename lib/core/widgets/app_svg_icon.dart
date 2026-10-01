import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Theme-aware outline icon shared by workbench navigation and controls.
class AppSvgIcon extends StatelessWidget {
  const AppSvgIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.color,
    this.semanticLabel,
  });

  final String name;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/icons/$name.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(
          color ??
              IconTheme.of(context).color ??
              Theme.of(context).colorScheme.onSurface,
          BlendMode.srcIn,
        ),
        semanticsLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
      );
}
