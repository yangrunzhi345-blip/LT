import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../core/widgets/app_page_scaffold.dart';
import '../../../../../../models/custom_attribute_item.dart';
import '../../../../../../l10n/generated/app_localizations.dart';
import '../../../../../../l10n/generated/app_localizations_zh.dart';

class DiceCheckPage extends StatefulWidget {
  const DiceCheckPage({
    super.key,
    required this.item,
    required this.characterName,
  });

  final CustomAttributeItem item;
  final String characterName;

  @override
  State<DiceCheckPage> createState() => _DiceCheckPageState();
}

class _DiceCheckPageState extends State<DiceCheckPage> {
  int? _rolledValue;
  String _verdict = '';
  Color _verdictColor = Colors.blue;
  String _verdictIcon = '🎲';
  late bool _usesD100 = widget.item.isNumeric;

  void _roll() {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final roll = _usesD100
        ? math.Random().nextInt(100) + 1
        : math.Random().nextInt(20) + 1;
    final target = widget.item.effectiveCurrentValue;
    late final String verdict;
    late final Color color;
    late final String icon;
    if (_usesD100) {
      (verdict, color, icon) = switch (roll) {
        <= 5 => (l10n.diceCriticalSuccess, Colors.amber, '✨'),
        >= 96 => (l10n.diceCriticalFailure, Colors.redAccent, '💥'),
        _ when roll <= target => (l10n.diceSuccess, Colors.green, '🛡️'),
        _ => (l10n.diceFailure, Colors.deepOrange, '⚠️'),
      };
    } else {
      (verdict, color, icon) = switch (roll) {
        20 => (l10n.diceCheckCriticalSuccess, Colors.amber, '✨'),
        1 => (l10n.diceCheckCriticalFailure, Colors.redAccent, '💥'),
        >= 10 => (l10n.diceCheckPassed, Colors.green, '🛡️'),
        _ => (l10n.diceCheckFailed, Colors.deepOrange, '⚠️'),
      };
    }
    setState(() {
      _rolledValue = roll;
      _verdict = verdict;
      _verdictColor = color;
      _verdictIcon = icon;
    });
  }

  void _submit() {
    final rolledValue = _rolledValue;
    if (rolledValue == null) return;
    final item = widget.item;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final targetDescription = item.isNumeric
        ? l10n.diceTargetValue(
            item.effectiveCurrentValue,
            item.effectiveMaxValue,
          )
        : l10n.diceCurrentStatus(item.value);
    final rule = item.description?.isNotEmpty == true
        ? l10n.diceRuleDescription(item.description!)
        : '';
    Navigator.of(context).pop(
      l10n.diceResultMessage(
        item.name,
        rule,
        widget.characterName,
        rolledValue,
        targetDescription,
        _verdict,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final scheme = Theme.of(context).colorScheme;
    return AppPageScaffold(
      title: '${l10n.characterStatusTitle} · ${item.name}',
      bottomBar: _rolledValue == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                key: const Key('dice-check-submit'),
                onPressed: _submit,
                icon: const Icon(Icons.send_rounded),
                label: Text(l10n.syncResultToAdventure),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${item.effectiveIcon} ${widget.characterName}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(item.isNumeric
              ? l10n.diceTargetValue(
                  item.effectiveCurrentValue,
                  item.effectiveMaxValue,
                )
              : l10n.diceCurrentStatus(item.value)),
          if (item.description?.isNotEmpty == true)
            Text(l10n.diceRuleDescription(item.description!)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.d100PercentileDie),
                selected: _usesD100,
                onSelected: (_) => setState(() => _usesD100 = true),
              ),
              ChoiceChip(
                label: Text(l10n.d20Die),
                selected: !_usesD100,
                onSelected: (_) => setState(() => _usesD100 = false),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const Key('dice-check-roll'),
              onPressed: _roll,
              icon: const Icon(Icons.casino_rounded),
              label: Text(_rolledValue == null
                  ? l10n.rollCheckAction
                  : l10n.rerollAction),
            ),
          ),
          if (_rolledValue != null) ...[
            const SizedBox(height: 20),
            DecoratedBox(
              decoration: BoxDecoration(
                color: _verdictColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _verdictColor.withValues(alpha: 0.4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                        l10n.diceResultPoints(
                          _verdictIcon,
                          _rolledValue!,
                          _usesD100 ? '/ 100' : '/ 20',
                        ),
                        style: TextStyle(
                          color: _verdictColor,
                          fontWeight: FontWeight.bold,
                        )),
                    const SizedBox(height: 8),
                    Text(_verdict,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _verdictColor)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(l10n.diceResultWillBeSent,
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
