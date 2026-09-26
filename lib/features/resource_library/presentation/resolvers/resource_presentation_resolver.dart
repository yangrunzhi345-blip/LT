import '../../../../application/resources/resource_lifecycle_projection.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../domain/models/resource_library_view_state.dart';

/// User-facing lifecycle projection states.
///
/// Distinct from internal engine and database states.
enum ResourcePresentationLifecycle {
  planning,
  generating,
  validating,
  ready,
  failed,
  cancelled,
  recovering,
  trashed,
  draft,
  paused,
  archived,
}

/// User-facing status filter in the Resource Library.
enum ResourceStatusFilter {
  all,
  ready,
  inProgress,
  draft,
  failed,
}

/// User-facing sorting options in the Resource Library.
enum ResourceSortOption {
  updatedDesc,
  updatedAsc,
  nameAsc,
  nameDesc,
}

/// Resolves user-facing lifecycle presentation, labels, filtering, and safety
/// sanitization for the Resource Library and Creation Workspace.
abstract final class ResourcePresentationResolver {
  static const List<String> _forbiddenPatterns = <String>[
    r'res_cre_[a-zA-Z0-9_]+',
    r'bp_[a-zA-Z0-9_]+',
    r'gen_cre_[a-zA-Z0-9_]+',
    r'att_[a-zA-Z0-9_]+',
    r'task_[a-zA-Z0-9_]+',
    r'char_internal[a-zA-Z0-9_]*',
    r'entityId',
    r'attributeId',
    r'statePath',
    r'revision',
    r'commitId',
    r'requestId',
    r'branchId',
    r'runtimeId',
    r'creationSessionId',
    r'generationId',
    r'attemptId',
    r'partId',
    r'cursor',
    r'CAS',
    r'file:\/\/\/[^\s]+',
    r'\/home\/[^\s]+',
    r'SELECT\s+.*?\s+FROM',
    r'INSERT\s+INTO',
    r'UPDATE\s+[a-zA-Z0-9_]+',
    r'StackTrace:?[^\n]*',
    r'Exception:?[^\n]*',
    r'---JSON---',
    r'\{"raw_json[^}]*\}',
    r'\{"protocol_version[^}]*\}',
  ];

  static final RegExp _sanitizerRegex = RegExp(
    _forbiddenPatterns.join('|'),
    caseSensitive: false,
  );

  /// Resolves the user-facing presentation lifecycle from a library item.
  static ResourcePresentationLifecycle resolveLifecycle({
    ResourceLifecycleState? lifecycleState,
    ResourceDisplayStatus? displayStatus,
    bool isConsumable = false,
  }) {
    if (lifecycleState != null) {
      return switch (lifecycleState) {
        ResourceLifecycleState.planning =>
          ResourcePresentationLifecycle.planning,
        ResourceLifecycleState.generating =>
          ResourcePresentationLifecycle.generating,
        ResourceLifecycleState.validating =>
          ResourcePresentationLifecycle.validating,
        ResourceLifecycleState.recovering =>
          ResourcePresentationLifecycle.recovering,
        ResourceLifecycleState.paused => ResourcePresentationLifecycle.paused,
        ResourceLifecycleState.failed => ResourcePresentationLifecycle.failed,
        ResourceLifecycleState.archived =>
          ResourcePresentationLifecycle.archived,
        ResourceLifecycleState.ready => ResourcePresentationLifecycle.ready,
        ResourceLifecycleState.draft => ResourcePresentationLifecycle.draft,
        ResourceLifecycleState.missing => ResourcePresentationLifecycle.draft,
      };
    }
    if (displayStatus != null) {
      return switch (displayStatus) {
        ResourceDisplayStatus.generating =>
          ResourcePresentationLifecycle.generating,
        ResourceDisplayStatus.optimizing =>
          ResourcePresentationLifecycle.validating,
        ResourceDisplayStatus.ready => ResourcePresentationLifecycle.ready,
        ResourceDisplayStatus.optimizationFailed =>
          ResourcePresentationLifecycle.failed,
        ResourceDisplayStatus.optimizationSuggested =>
          ResourcePresentationLifecycle.ready,
        ResourceDisplayStatus.saved => isConsumable
            ? ResourcePresentationLifecycle.ready
            : ResourcePresentationLifecycle.draft,
      };
    }
    return ResourcePresentationLifecycle.draft;
  }

  /// Maps presentation lifecycle to localized string.
  static String localizedLifecycleLabel(
    ResourcePresentationLifecycle lifecycle,
    AppLocalizations l10n,
  ) =>
      switch (lifecycle) {
        ResourcePresentationLifecycle.planning =>
          l10n.resourceLifecyclePlanning,
        ResourcePresentationLifecycle.generating =>
          l10n.resourceLifecycleGenerating,
        ResourcePresentationLifecycle.validating =>
          l10n.resourceLifecycleValidating,
        ResourcePresentationLifecycle.ready => l10n.resourceStatusReady,
        ResourcePresentationLifecycle.failed => l10n.resourceLifecycleFailed,
        ResourcePresentationLifecycle.cancelled =>
          l10n.resourceLifecycleCancelled,
        ResourcePresentationLifecycle.recovering =>
          l10n.resourceLifecycleRecovering,
        ResourcePresentationLifecycle.trashed => l10n.resourceLifecycleTrashed,
        ResourcePresentationLifecycle.draft => l10n.resourceLifecycleDraft,
        ResourcePresentationLifecycle.paused => l10n.resourceLifecyclePaused,
        ResourcePresentationLifecycle.archived =>
          l10n.resourceLifecycleArchived,
      };

  /// Returns localized status filter label.
  static String localizedStatusFilterLabel(
    ResourceStatusFilter filter,
    AppLocalizations l10n,
  ) =>
      switch (filter) {
        ResourceStatusFilter.all => l10n.resourceFilterStatusAll,
        ResourceStatusFilter.ready => l10n.resourceFilterStatusReady,
        ResourceStatusFilter.inProgress => l10n.resourceFilterStatusInProgress,
        ResourceStatusFilter.draft => l10n.resourceFilterStatusDraft,
        ResourceStatusFilter.failed => l10n.resourceFilterStatusFailed,
      };

  /// Returns localized sort option label.
  static String localizedSortLabel(
    ResourceSortOption sort,
    AppLocalizations l10n,
  ) =>
      switch (sort) {
        ResourceSortOption.updatedDesc => l10n.resourceSortUpdatedDesc,
        ResourceSortOption.updatedAsc => l10n.resourceSortUpdatedAsc,
        ResourceSortOption.nameAsc => l10n.resourceSortNameAsc,
        ResourceSortOption.nameDesc => l10n.resourceSortNameDesc,
      };

  /// Returns localized consumable badge string.
  static String isConsumableLabel(bool isConsumable, AppLocalizations l10n) =>
      isConsumable
          ? l10n.resourceConsumableBadge
          : l10n.resourceNotConsumableBadge;

  /// Returns non-null in-flight string if generating, validating, planning, or recovering.
  static String? inFlightStatusLabel(
    ResourcePresentationLifecycle lifecycle,
    AppLocalizations l10n,
  ) =>
      switch (lifecycle) {
        ResourcePresentationLifecycle.generating =>
          l10n.resourceInFlightGenerating,
        ResourcePresentationLifecycle.validating =>
          l10n.resourceInFlightValidating,
        ResourcePresentationLifecycle.recovering =>
          l10n.resourceInFlightRecovering,
        ResourcePresentationLifecycle.planning => l10n.resourceInFlightPlanning,
        _ => null,
      };

  /// Whether the lifecycle indicates active in-flight processing.
  static bool isInFlight(ResourcePresentationLifecycle lifecycle) =>
      lifecycle == ResourcePresentationLifecycle.generating ||
      lifecycle == ResourcePresentationLifecycle.validating ||
      lifecycle == ResourcePresentationLifecycle.recovering ||
      lifecycle == ResourcePresentationLifecycle.planning;

  /// Sanitizes text to remove any technical protocol markers, internal IDs,
  /// database paths, SQL statements, or exceptions.
  static String sanitize(String? text, {String fallback = ''}) {
    if (text == null) return fallback;
    final cleaned = text.replaceAll(_sanitizerRegex, '').trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  /// Returns a sanitized resource name, falling back to localized unnamed placeholder.
  static String safeName(String? name, AppLocalizations l10n) {
    final cleaned = sanitize(name);
    return cleaned.isEmpty ? l10n.resourceUnnamed : cleaned;
  }

  /// Returns a sanitized resource summary, falling back to localized empty summary placeholder.
  static String safeSummary(String? summary, AppLocalizations l10n) {
    final cleaned = sanitize(summary);
    return cleaned.isEmpty ? l10n.resourceNoSummary : cleaned;
  }

  /// Returns a safe display timestamp.
  static String safeUpdatedTime(String? timestamp, AppLocalizations l10n) {
    final cleaned = sanitize(timestamp);
    if (cleaned.isEmpty) return '';
    return l10n.resourceLastUpdated(cleaned);
  }

  /// Returns localized type label.
  static String localizedTypeLabel(ResourceType type, AppLocalizations l10n) =>
      switch (type) {
        ResourceType.worldview => l10n.resourceTypeWorldview,
        ResourceType.character => l10n.resourceTypeCharacter,
        ResourceType.npc => l10n.resourceTypeNpc,
      };
}
