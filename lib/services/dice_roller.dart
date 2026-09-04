import 'dart:math';

class DiceRoller {
  final _random = Random();

  static final _dicePattern = RegExp(r'(\d+)[dD](\d+)([+-]\d+)?');

  String parseAndRoll(String input) {
    final results = <String>[];
    final matches = _dicePattern.allMatches(input);
    if (matches.isEmpty) return '';

    for (final match in matches) {
      final count = int.tryParse(match.group(1) ?? '') ?? 0;
      final sides = int.tryParse(match.group(2) ?? '') ?? 0;
      final modifier = int.tryParse(match.group(3) ?? '') ?? 0;

      if (count <= 0 || sides <= 0) continue;
      if (count > 100) continue;

      final rolls = List.generate(count, (_) => _random.nextInt(sides) + 1);
      final sum = rolls.fold(0, (a, b) => a + b) + modifier;
      final rollStr = rolls.join(', ');

      String detail;
      if (count == 1) {
        detail = '$sum';
      } else {
        detail = '[$rollStr] = $sum';
      }
      if (modifier != 0) {
        detail += ' (含修正 ${modifier > 0 ? "+" : ""}$modifier)';
      }
      results.add('🎲 ${match.group(0)} → $detail');
    }
    return results.join('\n');
  }
}
