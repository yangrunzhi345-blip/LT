class DialogueLevel {
  final String id;
  final String label;
  final String description;
  final int minWords;
  final int maxWords;
  final bool openEnded;

  const DialogueLevel({
    required this.id,
    required this.label,
    required this.description,
    required this.minWords,
    required this.maxWords,
    this.openEnded = false,
  });

  String get wordRangeLabel =>
      openEnded ? '$minWords 字以上' : '$minWords-$maxWords 字';

  String get promptRequirement => openEnded
      ? '回复中文字数必须不少于 $minWords 字。'
      : '回复中文字数控制在 $minWords 到 $maxWords 字。';

  static const l0 = DialogueLevel(
    id: 'L0',
    label: '极速',
    description: '只保留关键反馈，适合快速确认。',
    minWords: 50,
    maxWords: 150,
    openEnded: true,
  );

  static const l1 = DialogueLevel(
    id: 'L1',
    label: '简洁',
    description: '简短推进，适合轻量互动。',
    minWords: 200,
    maxWords: 300,
    openEnded: true,
  );

  static const l2 = DialogueLevel(
    id: 'L2',
    label: '标准',
    description: '默认模式，兼顾速度和沉浸感。',
    minWords: 400,
    maxWords: 1000,
    openEnded: true,
  );

  static const l3 = DialogueLevel(
    id: 'L3',
    label: '详细',
    description: '更完整的描写和互动。',
    minWords: 1200,
    maxWords: 2000,
    openEnded: true,
  );

  static const l4 = DialogueLevel(
    id: 'L4',
    label: '深度',
    description: '强调铺垫、心理和场景层次。',
    minWords: 2500,
    maxWords: 3500,
    openEnded: true,
  );

  static const l5 = DialogueLevel(
    id: 'L5',
    label: '生产',
    description: '长文本生产，适合严肃写作。',
    minWords: 4500,
    maxWords: 10000,
    openEnded: true,
  );

  static const values = [l0, l1, l2, l3, l4, l5];
  static const defaultLevel = l2;

  static DialogueLevel fromId(String? id) {
    return values.firstWhere(
      (level) => level.id == id,
      orElse: () => defaultLevel,
    );
  }
}
