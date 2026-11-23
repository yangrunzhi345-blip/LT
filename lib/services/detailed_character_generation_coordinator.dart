import '../core/config/generation_limits.dart';
import 'character_card_generation_guard.dart';
import 'llm_service.dart';

enum CharacterGenerationPhase {
  anchor,
  profile,
  worldIntegration,
  roleplay,
  supplement,
  completed
}

class CharacterGenerationProgress {
  final CharacterGenerationPhase phase;
  final int currentCharacters;
  final int targetCharacters;
  final int supplementRound;
  final List<String> weakModules;

  const CharacterGenerationProgress({
    required this.phase,
    required this.currentCharacters,
    required this.targetCharacters,
    this.supplementRound = 0,
    this.weakModules = const [],
  });
}

class CharacterGenerationNoProgressException implements Exception {
  const CharacterGenerationNoProgressException();

  @override
  String toString() => '角色补全没有产生有效新增内容';
}

class CharacterGenerationTargetNotReachedException implements Exception {
  final CharacterCardGenerationReport report;

  const CharacterGenerationTargetNotReachedException(this.report);

  @override
  String toString() => '角色卡未能在安全补全轮数内达到完整度要求'
      '（${report.currentCharacters} / ${report.targetCharacters}）';
}

/// Runs the bounded Guard → supplement → merge → Guard state machine.
///
/// Transport and prompt construction remain outside this class so it can be
/// tested deterministically and reused by every character-generation entry.
final class DetailedCharacterGenerationCoordinator {
  final CharacterCardGenerationGuard guard;
  final int maximumSupplementRounds;

  const DetailedCharacterGenerationCoordinator({
    this.guard = const CharacterCardGenerationGuard(),
    this.maximumSupplementRounds =
        GenerationLimits.detailedCharacterMaximumSupplementRounds,
  });

  Future<Map<String, dynamic>> complete({
    required Map<String, dynamic> initial,
    required int targetTotalCharacters,
    required Future<Map<String, dynamic>> Function(
      Map<String, dynamic> candidate,
      CharacterCardGenerationReport report,
    ) requestSupplement,
    void Function(CharacterGenerationProgress progress)? onProgress,
    bool isNpc = false,
    GenerationTaskHandle? taskHandle,
  }) async {
    final target = targetTotalCharacters
        .clamp(
          GenerationLimits.detailedCharacterMinimumCharacters,
          GenerationLimits.detailedCharacterMaximumCharacters,
        )
        .toInt();
    var candidate = Map<String, dynamic>.from(initial);
    var report = guard.evaluate(
      card: candidate,
      targetCharacters: target,
      isNpc: isNpc,
    );
    for (var round = 1;
        round <= maximumSupplementRounds && !report.completed;
        round++) {
      _throwIfCancelled(taskHandle);
      onProgress?.call(CharacterGenerationProgress(
        phase: CharacterGenerationPhase.supplement,
        currentCharacters: report.currentCharacters,
        targetCharacters: target,
        supplementRound: round,
        weakModules: report.weakModules,
      ));
      final supplement = await requestSupplement(candidate, report);
      var next = mergeCharacterCardSupplement(candidate, supplement);
      var nextReport = guard.evaluate(
        card: next,
        targetCharacters: target,
        isNpc: isNpc,
      );
      // Handle no progress with bounded retries (max 2 extra attempts)
      int noProgressAttempts = 0;
      while (nextReport.currentCharacters <= report.currentCharacters &&
          noProgressAttempts < 2) {
        _throwIfCancelled(taskHandle);
        // Retry supplement request without advancing round count
        noProgressAttempts++;
        final retrySupplement = await requestSupplement(candidate, report);
        final retryNext =
            mergeCharacterCardSupplement(candidate, retrySupplement);
        final retryReport = guard.evaluate(
          card: retryNext,
          targetCharacters: target,
          isNpc: isNpc,
        );
        if (retryReport.currentCharacters > report.currentCharacters) {
          // Progress made, break out of retry loop
          next = retryNext;
          nextReport = retryReport;
          break;
        }
        // else continue retrying
      }
      if (nextReport.currentCharacters <= report.currentCharacters) {
        // No growth is only fatal when the card is still structurally
        // unusable. A structurally complete card may legitimately stop short
        // of the requested length; returning it preserves several rounds of
        // valid content instead of discarding them.
        if (_softComplete(nextReport)) {
          return _softReturn(next, nextReport, target, onProgress);
        }
        if (_softComplete(report)) {
          return _softReturn(candidate, report, target, onProgress);
        }
        throw const CharacterGenerationNoProgressException();
      }
      candidate = next;
      report = nextReport;
    }
    if (!report.completed) {
      if (_softComplete(report)) {
        return _softReturn(candidate, report, target, onProgress);
      }
      throw CharacterGenerationTargetNotReachedException(report);
    }
    onProgress?.call(CharacterGenerationProgress(
      phase: CharacterGenerationPhase.completed,
      currentCharacters: report.currentCharacters,
      targetCharacters: target,
      supplementRound: 0,
    ));
    return candidate;
  }

  /// A card that reaches the length cap with every required module ready is
  /// usable even when the requested character count is unmet; only a
  /// structurally broken card is a hard failure.
  static bool _softComplete(CharacterCardGenerationReport report) =>
      report.requiredModulesReady && report.structurallyConsistent;

  Map<String, dynamic> _softReturn(
    Map<String, dynamic> candidate,
    CharacterCardGenerationReport report,
    int target,
    void Function(CharacterGenerationProgress progress)? onProgress,
  ) {
    final result = Map<String, dynamic>.from(candidate)
      ..['generation_soft_incomplete'] = true;
    onProgress?.call(CharacterGenerationProgress(
      phase: CharacterGenerationPhase.completed,
      currentCharacters: report.currentCharacters,
      targetCharacters: target,
      supplementRound: 0,
    ));
    return result;
  }

  static void _throwIfCancelled(GenerationTaskHandle? taskHandle) {
    if (taskHandle?.isCancelled == true) {
      throw const GenerationCancelledException();
    }
  }

  /// Merges only incremental fields; identity anchors are immutable.
  static Map<String, dynamic> mergeCharacterCardSupplement(
    Map<String, dynamic> existing,
    Map<String, dynamic> supplement,
  ) {
    const identityFields = {'name', 'gender', 'age', 'profession'};
    final merged = Map<String, dynamic>.from(existing);
    for (final entry in supplement.entries) {
      if (identityFields.contains(entry.key)) continue;
      if (entry.key == 'world_profile') {
        final current = _map(merged[entry.key]);
        final addition = _map(entry.value);
        for (final profileEntry in addition.entries) {
          current[profileEntry.key] = _mergeValue(
            current[profileEntry.key],
            profileEntry.value,
          );
        }
        merged[entry.key] = current;
      } else {
        merged[entry.key] = _mergeValue(merged[entry.key], entry.value);
      }
    }
    return merged;
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static Object? _mergeValue(Object? existing, Object? addition) {
    if (addition is List) {
      return _dedupeStrings([
        if (existing is List) ...existing.map((item) => item.toString()),
        ...addition.map((item) => item.toString()),
      ]);
    }
    final current = existing?.toString().trim() ?? '';
    final next = addition?.toString().trim() ?? '';
    if (next.isEmpty || _normalize(current) == _normalize(next)) return current;
    if (current.isEmpty) return next;
    if (_normalize(current).contains(_normalize(next))) return current;
    if (_normalize(next).contains(_normalize(current))) return next;
    final overlap = _suffixPrefixOverlap(current, next);
    if (overlap >= 6) return current + next.substring(overlap);
    return '$current\n$next';
  }

  static List<String> _dedupeStrings(List<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (value.trim().isNotEmpty && seen.add(_normalize(value)))
          value.trim(),
    ];
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), '');

  static int _suffixPrefixOverlap(String left, String right) {
    final maximum = left.length < right.length ? left.length : right.length;
    for (var length = maximum; length >= 6; length--) {
      if (left.endsWith(right.substring(0, length))) return length;
    }
    return 0;
  }
}
