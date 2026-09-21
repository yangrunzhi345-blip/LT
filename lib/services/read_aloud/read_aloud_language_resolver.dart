import 'language_tag.dart';

/// 一次语言解析的结果。
///
/// 保留 `requested` 与 `resolved` 两个 tag，是为了让 UI 与调试都能知道“发生
/// 过 fallback”：当两者不同时，禁止把实际使用语言伪装成请求语言。
class ReadAloudLanguageResolution {
  const ReadAloudLanguageResolution({
    required this.requestedTag,
    required this.resolvedTag,
    required this.fallbackApplied,
    required this.unavailable,
  });

  /// 解析前请求的语言（自动检测结果或用户固定语言），归一化 BCP-47。
  final String requestedTag;

  /// 实际可用的语言；为 null 表示系统没有任何可用语言，无法朗读。
  final String? resolvedTag;

  /// 是否发生了语言降级（同家族 / 用户兜底 / 系统默认）。
  final bool fallbackApplied;

  /// 系统已知语言集合中没有任何可用语言。
  final bool unavailable;

  /// 实际使用的语言（不可用时退回请求语言，仅用于展示）。
  String get displayTag => resolvedTag ?? requestedTag;
}

/// 语言可用性解析：把“请求语言”映射到“系统真正能读的语言”。
///
/// 这是朗读自动语言的核心降级策略，纯函数、可单测，不触碰平台通道。
///
/// 关于“系统默认可用语言”：系统默认 voice 在各平台没有稳定可读的 API，因此
/// 本实现把用户配置的 [ReadAloudPreferences.languageTag] 同时当作“用户兜底”
/// 与“应用默认语言”；超过它之后不再猜测任意一个可用 locale 去念一段它并不
/// 属于的语言，而是显式报告 unavailable，交由 Authority 转成可见错误。
class ReadAloudLanguageResolver {
  const ReadAloudLanguageResolver();

  /// 按固定顺序解析 [requestedTag]：
  ///
  /// 1. 系统支持完全相同 tag → 直接使用；
  /// 2. 尝试同语言家族（primary subtag）的可用 locale（例如 `en-GB` → `en-US`）；
  /// 3. 用户兜底 [fallbackTag] 精确命中；
  /// 4. 用户兜底的同家族 locale；
  /// 5. 都没有 → [ReadAloudLanguageResolution.unavailable]。
  ///
  /// [availableLanguages] 为空表示“系统能力未知”（后端不提供枚举）：此时不
  /// 谎报支持、也不谎报不支持，而是乐观透传请求语言——因为否定证据不存在。
  ReadAloudLanguageResolution resolve({
    required String requestedTag,
    required List<String> availableLanguages,
    required String fallbackTag,
  }) {
    final requested = _normalizeOr(requestedTag, fallbackTag);
    final fallback = _normalizeOr(fallbackTag, requested);

    final available = _normalizedSet(availableLanguages);
    if (available.isEmpty) {
      return ReadAloudLanguageResolution(
        requestedTag: requested,
        resolvedTag: requested,
        fallbackApplied: false,
        unavailable: false,
      );
    }

    // 1. 完全相同。
    if (available.contains(requested)) {
      return ReadAloudLanguageResolution(
        requestedTag: requested,
        resolvedTag: requested,
        fallbackApplied: false,
        unavailable: false,
      );
    }

    // 2. 同语言家族。
    final familyMatch = _firstByFamily(available, languageFamily(requested));
    if (familyMatch != null) {
      return ReadAloudLanguageResolution(
        requestedTag: requested,
        resolvedTag: familyMatch,
        fallbackApplied: true,
        unavailable: false,
      );
    }

    // 3. 用户兜底语言。
    if (available.contains(fallback)) {
      return ReadAloudLanguageResolution(
        requestedTag: requested,
        resolvedTag: fallback,
        fallbackApplied: true,
        unavailable: false,
      );
    }

    // 4. 用户兜底的同家族 locale。
    final fallbackFamilyMatch =
        _firstByFamily(available, languageFamily(fallback));
    if (fallbackFamilyMatch != null) {
      return ReadAloudLanguageResolution(
        requestedTag: requested,
        resolvedTag: fallbackFamilyMatch,
        fallbackApplied: true,
        unavailable: false,
      );
    }

    // 5. 系统已知语言集合里没有任何可接受的降级目标。
    return ReadAloudLanguageResolution(
      requestedTag: requested,
      resolvedTag: null,
      fallbackApplied: false,
      unavailable: true,
    );
  }

  static Set<String> _normalizedSet(List<String> tags) {
    final result = <String>{};
    for (final tag in tags) {
      final normalized = normalizeBcp47(tag);
      if (normalized.isNotEmpty) result.add(normalized);
    }
    return result;
  }

  static String? _firstByFamily(Set<String> available, String? family) {
    if (family == null) return null;
    final matches = available
        .where((tag) => languageFamily(tag) == family)
        .toList()
      ..sort();
    return matches.isEmpty ? null : matches.first;
  }

  static String _normalizeOr(String tag, String fallback) {
    final normalized = normalizeBcp47(tag);
    if (normalized.isNotEmpty) return normalized;
    final normalizedFallback = normalizeBcp47(fallback);
    return normalizedFallback.isEmpty ? tag : normalizedFallback;
  }
}
