/// Structured hints derived from a player message without replacing it.
final class NarrativeIntent {
  final String rawInput;
  final List<String> actions;
  final List<String> goals;
  final List<String> refusals;
  final List<String> constraints;
  final List<String> excludedCharacterIds;
  final bool changesPreviousGoal;
  final bool asksHistory;
  final bool asksCause;

  const NarrativeIntent({
    required this.rawInput,
    this.actions = const [],
    this.goals = const [],
    this.refusals = const [],
    this.constraints = const [],
    this.excludedCharacterIds = const [],
    this.changesPreviousGoal = false,
    this.asksHistory = false,
    this.asksCause = false,
  });
}

/// Conservatively extracts explicit player intent from Chinese or English.
///
/// Ambiguous prose is deliberately left in [NarrativeIntent.rawInput]. The
/// resolver never invents an action and only resolves character names from the
/// supplied adventure roster.
final class IntentResolver {
  static final RegExp _negativePrefix = RegExp(
    r'^(?:我)?(?:先)?(?:不要|不再|不去|别让|别|取消|停止|拒绝|放弃|no\b|not\b|don[’\x27]?t\b|stop\b|cancel\b)',
    caseSensitive: false,
  );

  const IntentResolver();

  NarrativeIntent resolve(
    String rawInput, {
    Map<String, String> knownCharacters = const {},
  }) {
    final clauses = rawInput
        .split(RegExp(r'[，,。！？!?；;\n]+'))
        .map((clause) => clause.trim())
        .where((clause) => clause.isNotEmpty)
        .toList(growable: false);
    final actions = <String>[];
    final goals = <String>[];
    final refusals = <String>[];
    final constraints = <String>[];
    final excludedCharacterIds = <String>[];
    final lowerInput = rawInput.toLowerCase();
    final asksCause =
        RegExp(r'为什么|怎么变成|发生了什么|\bwhy\b|\bhow\b').hasMatch(lowerInput);
    final asksHistory = asksCause ||
        RegExp(r'以前|曾经|当时|何时|历史|\bbefore\b|\bpreviously\b|\bwhen\b|\bhistory\b')
            .hasMatch(lowerInput);

    for (final clause in clauses) {
      if (_negativePrefix.hasMatch(clause)) {
        refusals.add(clause);
      } else if (_looksLikeGoal(clause)) {
        goals.add(clause);
        actions.add(clause);
      } else {
        actions.add(clause);
      }

      final lowerClause = clause.toLowerCase();
      for (final entry in knownCharacters.entries) {
        if (!clause.contains(entry.value)) continue;
        final excludes = clause.contains('不要让${entry.value}') ||
            clause.contains('别让${entry.value}') ||
            clause.contains('${entry.value}不要跟') ||
            clause.contains('${entry.value}不同行') ||
            (lowerClause.contains(entry.value.toLowerCase()) &&
                (lowerClause.contains("don't follow") ||
                    lowerClause.contains('do not follow') ||
                    lowerClause.contains('without')));
        if (excludes && !excludedCharacterIds.contains(entry.key)) {
          excludedCharacterIds.add(entry.key);
          constraints.add(clause);
        }
      }
    }

    return NarrativeIntent(
      rawInput: rawInput,
      actions: List.unmodifiable(actions),
      goals: List.unmodifiable(goals),
      refusals: List.unmodifiable(refusals),
      constraints: List.unmodifiable(constraints),
      excludedCharacterIds: List.unmodifiable(excludedCharacterIds),
      changesPreviousGoal: refusals.isNotEmpty && goals.isNotEmpty,
      asksHistory: asksHistory,
      asksCause: asksCause,
    );
  }

  bool _looksLikeGoal(String clause) {
    final lower = clause.toLowerCase();
    return RegExp(
      r'(?:我要|我想|我决定|我去|前往|寻找|调查|帮助|背叛|邀请|尝试|i want|i will|i decide|go to|find|help|betray|invite|try)',
      caseSensitive: false,
    ).hasMatch(lower);
  }
}
