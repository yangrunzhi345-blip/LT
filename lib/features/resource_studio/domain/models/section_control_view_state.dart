import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/section_control.dart';
import '../../../../domain/errors/app_error.dart';

enum SectionControlNoticeType {
  validationPassed,
  validationFailed,
  validationComplete,
  regenerated,
  generationFailed,
  generationComplete,
}

final class SectionControlNotice {
  const SectionControlNotice({
    required this.type,
    this.title = '',
    this.count = 0,
    this.completedParts = 0,
    this.totalParts = 0,
    this.detail = '',
  });

  final SectionControlNoticeType type;
  final String title;
  final int count;
  final int completedParts;
  final int totalParts;
  final String detail;
}

/// Presentation status of the section controls panel.
enum SectionControlViewStatus {
  idle,
  loading,
  ready,
  working,
  failed,
}

/// Immutable state exposed by [SectionControlController].
final class SectionControlViewState {
  const SectionControlViewState({
    required this.status,
    this.resourceId,
    this.entries = const <SectionControlEntry>[],
    this.totalCount = 0,
    this.hasMore = false,
    this.busySectionIds = const <String>{},
    this.errorMessage = '',
    this.lastNotice,
    this.error,
  });

  const SectionControlViewState.initial()
      : this(status: SectionControlViewStatus.idle);

  final SectionControlViewStatus status;
  final ResourceId? resourceId;
  final List<SectionControlEntry> entries;
  final int totalCount;
  final bool hasMore;

  /// Sections with an operation currently in flight, so only those rows show a
  /// spinner instead of the whole list appearing to be busy.
  final Set<String> busySectionIds;

  final String errorMessage;
  final SectionControlNotice? lastNotice;
  final AppDomainError? error;

  bool get isLoading => status == SectionControlViewStatus.loading;

  bool get isEmpty =>
      entries.isEmpty && status != SectionControlViewStatus.loading;

  bool isBusy(String sectionId) => busySectionIds.contains(sectionId);

  SectionControlViewState copyWith({
    SectionControlViewStatus? status,
    ResourceId? resourceId,
    List<SectionControlEntry>? entries,
    int? totalCount,
    bool? hasMore,
    Set<String>? busySectionIds,
    String? errorMessage,
    SectionControlNotice? lastNotice,
    bool clearNotice = false,
    AppDomainError? error,
  }) {
    return SectionControlViewState(
      status: status ?? this.status,
      resourceId: resourceId ?? this.resourceId,
      entries: entries ?? this.entries,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      busySectionIds: busySectionIds ?? this.busySectionIds,
      errorMessage: errorMessage ?? this.errorMessage,
      lastNotice: clearNotice ? null : (lastNotice ?? this.lastNotice),
      error: error ?? this.error,
    );
  }
}
