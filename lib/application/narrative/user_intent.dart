/// Structured hints derived from a player message without replacing it.
final class NarrativeIntent {
  final String rawInput;
  final List<String> actions;
  final List<String> goals;
  final List<String> refusals;
  final List<String> constraints;
  final List<String> excludedCharacterIds;

  /// Roster ids the player explicitly asked to join the scene this turn
  /// (「叫 C 一起来」/「invite C」). An invitation is an authorization, not a
  /// guarantee: the model still has to depict the arrival.
  final List<String> invitedCharacterIds;

  /// Roster ids the player explicitly asked to leave the scene this turn
  /// (「让 C 先走」/「ask C to leave」).
  final List<String> dismissedCharacterIds;

  /// Roster ids the player wants to be alone with (「我想单独和 A 相处」).
  /// Other present characters must not actively interrupt; this is a soft
  /// constraint, not a hard presence exclusion.
  final List<String> privateWithCharacterIds;

  /// 「慢一点」「一步一步来」— the player asked for a slower, more gradual
  /// unfolding instead of compressed progress.
  final bool wantsSlowerPace;

  /// 「暂时不要换场景」— a location change proposed by the model this turn is
  /// a deterministic violation of an explicit player constraint.
  final bool forbidsSceneChange;

  /// 「我们去王宫吧」「换个地方」— the player authorized a scene move.
  final bool requestsSceneChange;

  /// 「不要跳时间」「不要跳过这段过程」— a time delta proposed by the model is
  /// a deterministic violation of an explicit player constraint.
  final bool forbidsTimeSkip;

  /// 「直接跳到第二天」— the player authorized a time jump.
  final bool requestsTimeSkip;

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
    this.invitedCharacterIds = const [],
    this.dismissedCharacterIds = const [],
    this.privateWithCharacterIds = const [],
    this.wantsSlowerPace = false,
    this.forbidsSceneChange = false,
    this.requestsSceneChange = false,
    this.forbidsTimeSkip = false,
    this.requestsTimeSkip = false,
    this.changesPreviousGoal = false,
    this.asksHistory = false,
    this.asksCause = false,
  });
}

/// Conservatively extracts explicit player intent from Chinese or English.
///
/// Ambiguous prose is deliberately left in [NarrativeIntent.rawInput]. The
/// resolver never invents an action and only resolves character names from
/// the supplied adventure roster.
///
/// The added soft-constraint signals (pace, privacy, scene/time guards) are
/// deliberately conservative: they only fire on explicit phrasings and are
/// always advisory to the prompt or to deterministic veto checks. They never
/// rewrite the raw player input, which stays the final authority.
final class IntentResolver {
  static final RegExp _negativePrefix = RegExp(
    r'^(?:我)?(?:先)?(?:不要|不再|不去|别让|不想让|不想|不让|不许|别|取消|停止|拒绝|放弃|no\b|not\b|don[’\x27]?t\b|stop\b|cancel\b)',
    caseSensitive: false,
  );

  /// Pacing requests. Matched inside any clause; the negation-safe entries
  /// (「不要急」) are listed explicitly because 「不急」 is not a substring.
  static final RegExp _slowerPacePattern = RegExp(
    r'慢一点|慢些|慢慢来|不要急|别急|放缓|一步一步|逐步来|slow down|take it slow',
    caseSensitive: false,
  );

  /// Explicit "do not move the scene" constraints. These carry their own
  /// negation so they also fire inside negative clauses.
  static final RegExp _forbidSceneChangePattern = RegExp(
    r'暂时不要换场景|不要换场景|别换场景|不换地方|先不换地方|别去别的地方|就待在这|待在这别动|'
    r"stay here|don'?t move|don'?t change (?:the )?scene|no scene change",
    caseSensitive: false,
  );

  /// Explicit "do not skip ahead in time" constraints.
  static final RegExp _forbidTimeSkipPattern = RegExp(
    r'不要跳时间|别跳时间|不要跳到|别跳到|不要跳过|别跳过|不要快进|别快进|跳过这段|不要跳这段|'
    r"don'?t skip|no skipping|don'?t skip ahead|don'?t jump",
    caseSensitive: false,
  );

  /// Positive scene/time authorizations. Only honored on non-negative clauses
  /// so 「别跳到第二天」 can never be read as a request.
  static final RegExp _requestSceneChangePattern = RegExp(
    r'换个地方|换场景|离开这里|我们去|前往|走吧|动身|go to|head to|'
    r"let'?s go|move to|leave here",
    caseSensitive: false,
  );

  static final RegExp _requestTimeSkipPattern = RegExp(
    r'直接跳到|快进到|跳到|快进|skip to|time skip|jump to',
    caseSensitive: false,
  );

  /// 「我想单独和 A 相处」 → capture A. English uses "alone with".
  static final RegExp _privacyPattern =
      RegExp(r'单独和|单独跟|只想和|想和.{0,4}单独|和.{0,6}单独|alone with');

  /// Verbs that mean a character would join, accompany or interrupt the
  /// scene. Used by the complementary exclusion rule; deliberately free of
  /// generic words like 「在」 or a bare 「跟」 (「跟…说」 is speech, not
  /// participation) that appear in unrelated negatives.
  static final RegExp _participationVerbs =
      RegExp(r'跟来|跟上|跟着|同行|一起|打扰|参与|出声|插话|掺和|靠近|过来|加入|来');

  /// The unambiguous subset of [_participationVerbs] with no bare 「来」. A
  /// protective negative (「别让艾拉担心我来晚了」) contains an unrelated 「来」,
  /// so only these unambiguous verbs may cancel its protection.
  static final RegExp _accompanyingVerbs =
      RegExp(r'跟来|跟上|跟着|同行|一起|打扰|参与|出声|插话|掺和|靠近|过来|加入');

  /// Verbs that make a negative clause about information rather than
  /// participation (「别让艾琳知道」 is secrecy, not exclusion). No bare 「提」
  /// so 「提前」 is never read as information.
  static final RegExp _protectiveVerbs =
      RegExp(r'告诉|知道|担心|操心|提及|提起|提醒|提议|听说|看到|察觉|发现|说');

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
    final invitedCharacterIds = <String>[];
    final dismissedCharacterIds = <String>[];
    final privateWithCharacterIds = <String>[];
    final lowerInput = rawInput.toLowerCase();
    final asksCause =
        RegExp(r'为什么|怎么变成|发生了什么|\bwhy\b|\bhow\b').hasMatch(lowerInput);
    final asksHistory = asksCause ||
        RegExp(r'以前|曾经|当时|何时|历史|\bbefore\b|\bpreviously\b|\bwhen\b|\bhistory\b')
            .hasMatch(lowerInput);

    // Longest names first so 「艾琳娜」 wins over 「艾琳」 inside one clause.
    final roster = knownCharacters.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    var wantsSlowerPace = false;
    var forbidsSceneChange = false;
    var requestsSceneChange = false;
    var forbidsTimeSkip = false;
    var requestsTimeSkip = false;

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
      final negative = _negativePrefix.hasMatch(clause);

      if (_slowerPacePattern.hasMatch(lowerClause)) wantsSlowerPace = true;
      if (_forbidSceneChangePattern.hasMatch(lowerClause)) {
        forbidsSceneChange = true;
        constraints.add(clause);
      }
      if (_forbidTimeSkipPattern.hasMatch(lowerClause)) {
        forbidsTimeSkip = true;
        constraints.add(clause);
      }
      if (!negative && _requestSceneChangePattern.hasMatch(lowerClause)) {
        requestsSceneChange = true;
      }
      if (!negative && _requestTimeSkipPattern.hasMatch(lowerClause)) {
        requestsTimeSkip = true;
      }

      for (final entry in roster) {
        final id = entry.key;
        final name = entry.value;
        if (name.isEmpty || !clause.contains(name)) continue;
        final lowerName = name.toLowerCase();

        // Exclusion is checked first so 「不要让 C 来」 can never be read as
        // an invitation of C. A clause about information (「别让艾琳知道」)
        // is secrecy, not exclusion, unless it also asks the character to
        // stay away from the scene.
        final mentionsParticipation = _participationVerbs.hasMatch(clause);
        // A protective statement is only overridden when the clause also asks
        // the character to *accompany* — an unrelated 「来」 is not enough.
        final isProtective = _protectiveVerbs.hasMatch(clause) &&
            !_accompanyingVerbs.hasMatch(clause);
        final excludes = !isProtective &&
            (clause.contains('不要让$name') ||
                clause.contains('别让$name') ||
                clause.contains('不要$name') ||
                clause.contains('别$name') ||
                clause.contains('不想$name') ||
                clause.contains('不让$name') ||
                clause.contains('$name不要跟') ||
                clause.contains('$name别跟') ||
                clause.contains('$name不同行') ||
                clause.contains('$name别来') ||
                clause.contains('$name别打扰') ||
                clause.contains('$name别掺和') ||
                clause.contains('$name不许') ||
                // Complementary rule for multi-name negatives such as
                // 「别让艾琳和鲍里斯跟来」: a negated clause about
                // accompanying, interrupting or participating excludes every
                // roster name it mentions.
                (negative && mentionsParticipation) ||
                (lowerClause.contains(lowerName) &&
                    (lowerClause.contains("don't follow") ||
                        lowerClause.contains('do not follow') ||
                        lowerClause.contains('without') ||
                        lowerClause.contains('keep $lowerName away') ||
                        lowerClause.contains("don't let $lowerName") ||
                        lowerClause.contains('no $lowerName'))));
        if (excludes) {
          if (!excludedCharacterIds.contains(id)) excludedCharacterIds.add(id);
          constraints.add(clause);
          continue;
        }

        final invites = clause.contains('让$name来') ||
            clause.contains('叫$name来') ||
            clause.contains('请$name来') ||
            clause.contains('邀请$name') ||
            clause.contains('带$name来') ||
            clause.contains('带$name一起') ||
            clause.contains('$name也来') ||
            clause.contains('$name一起来') ||
            clause.contains('叫上$name') ||
            clause.contains('约$name来') ||
            clause.contains('把$name叫来') ||
            (lowerClause.contains(lowerName) &&
                (lowerClause.contains('invite $lowerName') ||
                    lowerClause.contains('ask $lowerName to come') ||
                    lowerClause.contains('bring $lowerName') ||
                    lowerClause.contains('call $lowerName over') ||
                    lowerClause.contains('have $lowerName join')));
        if (invites) {
          if (!invitedCharacterIds.contains(id)) invitedCharacterIds.add(id);
          continue;
        }

        final dismisses = clause.contains('让$name走') ||
            clause.contains('叫$name离开') ||
            clause.contains('请$name离开') ||
            clause.contains('$name先走') ||
            clause.contains('$name回去吧') ||
            clause.contains('让$name先离开') ||
            (lowerClause.contains(lowerName) &&
                (lowerClause.contains('send $lowerName away') ||
                    lowerClause.contains('ask $lowerName to leave') ||
                    lowerClause.contains('dismiss $lowerName')));
        if (dismisses) {
          if (!dismissedCharacterIds.contains(id)) {
            dismissedCharacterIds.add(id);
          }
          continue;
        }

        if (_privacyPattern.hasMatch(clause) &&
            !privateWithCharacterIds.contains(id)) {
          privateWithCharacterIds.add(id);
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
      invitedCharacterIds: List.unmodifiable(invitedCharacterIds),
      dismissedCharacterIds: List.unmodifiable(dismissedCharacterIds),
      privateWithCharacterIds: List.unmodifiable(privateWithCharacterIds),
      wantsSlowerPace: wantsSlowerPace,
      forbidsSceneChange: forbidsSceneChange,
      requestsSceneChange: requestsSceneChange,
      forbidsTimeSkip: forbidsTimeSkip,
      requestsTimeSkip: requestsTimeSkip,
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
