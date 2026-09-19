import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../core/widgets/app_page_scaffold.dart';
import '../../../../../../models/custom_attribute_item.dart';

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
    final roll = _usesD100
        ? math.Random().nextInt(100) + 1
        : math.Random().nextInt(20) + 1;
    final target = widget.item.effectiveCurrentValue;
    late final String verdict;
    late final Color color;
    late final String icon;
    if (_usesD100) {
      (verdict, color, icon) = switch (roll) {
        <= 5 => ('大成功 (Critical Success)！判定完美达成！', Colors.amber, '✨'),
        >= 96 => ('大失败 (Fumble)！遭遇严重失误或异常反噬！', Colors.redAccent, '💥'),
        _ when roll <= target => ('检定成功！成功抵抗异常并维持状态稳定。', Colors.green, '🛡️'),
        _ => ('检定失败！受到状态影响或负面效果侵扰。', Colors.deepOrange, '⚠️'),
      };
    } else {
      (verdict, color, icon) = switch (roll) {
        20 => ('大成功 (暴击)！极限突破达成！', Colors.amber, '✨'),
        1 => ('大失败！判定彻底失败！', Colors.redAccent, '💥'),
        >= 10 => ('检定通过！状态运转顺利。', Colors.green, '🛡️'),
        _ => ('检定未通过！受到阻碍或负面波及。', Colors.deepOrange, '⚠️'),
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
    final targetDescription = item.isNumeric
        ? '目标值 ${item.effectiveCurrentValue}'
        : '当前状态 ${item.value}';
    final rule =
        item.description?.isNotEmpty == true ? '（规则：${item.description}）' : '';
    Navigator.of(context).pop(
      '【状态检测】${widget.characterName} 进行了「${item.name}」检定：'
      '🎲 掷出 $rolledValue ($targetDescription) -> 【$_verdict】！$rule',
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final scheme = Theme.of(context).colorScheme;
    return AppPageScaffold(
      title: '状态检定 · ${item.name}',
      bottomBar: _rolledValue == null
          ? null
          : Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                key: const Key('dice-check-submit'),
                onPressed: _submit,
                icon: const Icon(Icons.send_rounded),
                label: const Text('同步至冒险剧情'),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${item.effectiveIcon} ${widget.characterName}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(item.isNumeric
              ? '检定目标值: ${item.effectiveCurrentValue} / ${item.effectiveMaxValue}'
              : '当前状态: ${item.value}'),
          if (item.description?.isNotEmpty == true)
            Text('判定规则: ${item.description}'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('D100 百分比骰'),
                selected: _usesD100,
                onSelected: (_) => setState(() => _usesD100 = true),
              ),
              ChoiceChip(
                label: const Text('D20 骰'),
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
              label: Text(_rolledValue == null ? '投掷检测骰' : '重新投掷'),
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
                        '$_verdictIcon 掷出点数: $_rolledValue ${_usesD100 ? '/ 100' : '/ 20'}',
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
          Text('检定结果将作为一条用户消息发送。',
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
