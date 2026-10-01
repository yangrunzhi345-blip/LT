import 'package:flutter/material.dart';

import 'app_svg_icon.dart';

/// Semantic icon identities for [CustomAttributeItem.icon].
///
/// New custom attributes persist one of these identifiers instead of an emoji.
/// Legacy rows that still store an emoji keep rendering through
/// [resolveCustomAttributeIconId], so no schema migration is required.
const Set<String> customAttributeIconIds = <String>{
  'mind',
  'affinity',
  'corruption',
  'flame',
  'bolt',
  'droplet',
  'sustenance',
  'ward',
  'insight',
  'arcana',
  'star',
  'arms',
  'blood',
  'remedy',
  'radiance',
  'tempest',
};

/// Legacy emoji → semantic id, covering every seed value this app ever wrote
/// plus the inference defaults produced by `CustomAttributeItem.effectiveIcon`.
const Map<String, String> _legacyEmojiToId = <String, String>{
  '🧠': 'mind',
  '❤️': 'affinity',
  '❤': 'affinity',
  '☣️': 'corruption',
  '☣': 'corruption',
  '🔥': 'flame',
  '⚡': 'bolt',
  '💧': 'droplet',
  '🍖': 'sustenance',
  '🛡️': 'ward',
  '🛡': 'ward',
  '👁️': 'insight',
  '👁': 'insight',
  '🔮': 'arcana',
  '⭐': 'star',
  '⚔️': 'arms',
  '⚔': 'arms',
  '🩸': 'blood',
  '💊': 'remedy',
  '✨': 'radiance',
  '🌪️': 'tempest',
  '🌪': 'tempest',
  '🔍': 'insight',
};

/// Resolves a stored custom-attribute icon — a new semantic id or a legacy
/// emoji — to a canonical semantic id, or `null` when unrecognised.
String? resolveCustomAttributeIconId(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  if (customAttributeIconIds.contains(value)) return value;
  return _legacyEmojiToId[value];
}

/// Renders a [CustomAttributeItem] icon from its semantic id or legacy emoji.
///
/// Unknown stored values fall back to their text form so user-authored data is
/// never dropped.
class CustomAttributeIcon extends StatelessWidget {
  const CustomAttributeIcon(
    this.raw, {
    super.key,
    this.size = 18,
    this.color,
  });

  final String? raw;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final id = resolveCustomAttributeIconId(raw);
    if (id != null) {
      return AppSvgIcon(id, size: size, color: color);
    }
    final text = raw?.trim() ?? '';
    if (text.isEmpty) {
      return SizedBox(width: size, height: size);
    }
    return Text(
      text,
      style: TextStyle(fontSize: size * 0.9, color: color),
    );
  }
}
