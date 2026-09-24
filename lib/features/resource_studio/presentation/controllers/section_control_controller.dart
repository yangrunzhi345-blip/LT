import 'dart:async';
import '../resource_studio_user_message.dart';
import '../../../../core/localization/app_error_localizer.dart';

import 'package:flutter/foundation.dart';

import '../../../../application/resources/section_control_service.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../domain/resources/section_control.dart';
import '../../../../domain/resources/section_control_events.dart';
import '../../application/use_cases/section_control_runtime.dart';
import '../../domain/models/section_control_view_state.dart';

/// View-model for the Studio section controls.
///
/// The database (through the service) is the single source of truth: after any
/// mutation the controller re-reads the first page instead of merging edits
/// locally, so the list can never drift from persisted state. Paging keeps the
/// read bounded, and runtime events only trigger a debounced refresh of that
/// same first page.
final class SectionControlController extends ChangeNotifier {
  SectionControlController({
    required SectionControlRuntime runtime,
    this.pageSize = 20,
    this.eventRefreshDelay = const Duration(milliseconds: 250),
  }) : _runtime = runtime;

  final SectionControlRuntime _runtime;

  /// Sections read per page. Small on purpose: a resource can hold dozens of
  /// sections and the panel only ever needs one page at a time.
  final int pageSize;

  /// Coalescing window for event-driven refreshes.
  final Duration eventRefreshDelay;

  StreamSubscription<SectionControlEvent>? _eventsSubscription;
  Timer? _refreshTimer;
  SectionControlViewState _state = const SectionControlViewState.initial();
  bool _disposed = false;

  /// Monotonic request token. [load] bumps it when the tracked resource
  /// changes; every async publish re-validates the token it captured so a
  /// slow result for an older resource/request can never overwrite the
  /// current one (A/B inversion, resource switch, stale error).
  int _generation = 0;

  SectionControlViewState get state => _state;

  /// Starts (or restarts) tracking one resource's sections.
  Future<void> load(ResourceId resourceId) async {
    if (_disposed) return;
    _generation++;
    _state = SectionControlViewState(
      status: SectionControlViewStatus.loading,
      resourceId: resourceId,
      entries: _state.resourceId == resourceId
          ? _state.entries
          : const <SectionControlEntry>[],
    );
    notifyListeners();

    _eventsSubscription ??= _runtime.events.listen((_) => _scheduleRefresh());
    await _reloadFirstPage();
  }

  Future<void> refresh() => _reloadFirstPage();

  /// Appends the next page to the current list.
  Future<void> loadMore() async {
    final resourceId = _state.resourceId;
    if (_disposed || resourceId == null || !_state.hasMore) return;

    final generation = _generation;
    final offset = _state.entries.length;
    _setState(_state.copyWith(status: SectionControlViewStatus.working));
    try {
      final page = await _runtime.listSections(
        resourceId: resourceId,
        limit: pageSize,
        offset: offset,
      );
      if (_disposed ||
          generation != _generation ||
          _state.resourceId != resourceId) {
        // The tracked resource changed while this page was in flight; the
        // merged list would mix two resources, so discard it.
        return;
      }
      final merged = <SectionControlEntry>[
        ..._state.entries,
        for (final entry in page.entries)
          if (!_state.entries.any((existing) => existing.id == entry.id)) entry,
      ];
      _setState(_state.copyWith(
        status: SectionControlViewStatus.ready,
        entries: merged,
        totalCount: page.totalCount,
        hasMore: merged.length < page.totalCount,
        errorMessage: '',
      ));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _fail(error);
    }
  }

  Future<bool> createSection(String title) => _run(
        (resourceId) => _runtime.createSection(
          resourceId: resourceId,
          title: title,
        ),
        busyId: null,
      );

  Future<bool> renameSection(SectionControlEntry entry, String title) => _run(
        (_) => _runtime.renameSection(
          id: entry.id,
          title: title,
          expectedUpdatedAt: entry.updatedAtToken,
        ),
        busyId: entry.id.value,
      );

  Future<bool> deleteSection(SectionControlEntry entry) => _run(
        (_) async {
          await _runtime.deleteSection(
            id: entry.id,
            expectedUpdatedAt: entry.updatedAtToken,
          );
          return null;
        },
        busyId: entry.id.value,
      );

  Future<bool> moveSection(SectionControlEntry entry, int targetIndex) => _run(
        (resourceId) async {
          await _runtime.moveSection(
            resourceId: resourceId,
            id: entry.id,
            targetIndex: targetIndex,
            expectedUpdatedAt: entry.updatedAtToken,
          );
          return null;
        },
        busyId: entry.id.value,
      );

  Future<bool> validateSection(SectionControlEntry entry) => _run(
        (_) => _runtime.validateSection(entry.id),
        busyId: entry.id.value,
        successNotice: (result) => result is SectionValidationResult
            ? SectionControlNotice(
                type: result.isValid
                    ? SectionControlNoticeType.validationPassed
                    : SectionControlNoticeType.validationFailed,
                title: entry.title,
                count: result.issues.length,
              )
            : const SectionControlNotice(
                type: SectionControlNoticeType.validationComplete,
              ),
      );

  Future<bool> regenerateSection(SectionControlEntry entry) => _run(
        (_) => _runtime.regenerateSection(
          id: entry.id,
          expectedUpdatedAt: entry.updatedAtToken,
        ),
        busyId: entry.id.value,
        successNotice: (result) => result is SectionGenerationOutcome
            ? SectionControlNotice(
                type: result.success
                    ? SectionControlNoticeType.regenerated
                    : SectionControlNoticeType.generationFailed,
                title: entry.title,
                completedParts: result.completedPartCount,
                totalParts: result.partCount,
                detail: result.success
                    ? ''
                    : result.error == null
                        ? ''
                        : result.error!.code.name,
              )
            : const SectionControlNotice(
                type: SectionControlNoticeType.generationComplete,
              ),
      );

  /// Runs one section operation, then refreshes from persisted state.
  Future<bool> _run(
    Future<Object?> Function(ResourceId resourceId) action, {
    required String? busyId,
    SectionControlNotice Function(Object? result)? successNotice,
  }) async {
    final resourceId = _state.resourceId;
    if (_disposed || resourceId == null) return false;

    final generation = _generation;
    _setBusy(busyId, true);
    try {
      final result = await action(resourceId);
      await _reloadFirstPage();
      if (_disposed || generation != _generation) return true;
      _setState(_state.copyWith(
        lastNotice: successNotice?.call(result),
        clearNotice: successNotice == null,
        errorMessage: '',
      ));
      return true;
    } catch (error) {
      if (_disposed || generation != _generation) return false;
      _fail(error);
      return false;
    } finally {
      _setBusy(busyId, false);
    }
  }

  Future<void> _reloadFirstPage() async {
    final resourceId = _state.resourceId;
    if (_disposed || resourceId == null) return;
    final generation = _generation;
    try {
      final page = await _runtime.listSections(
        resourceId: resourceId,
        limit: pageSize,
        offset: 0,
      );
      if (_disposed ||
          generation != _generation ||
          _state.resourceId != resourceId) {
        // A newer load/refresh superseded this one; publishing the stale page
        // would roll the visible list back or attach it to another resource.
        return;
      }
      _setState(_state.copyWith(
        status: SectionControlViewStatus.ready,
        entries: page.entries,
        totalCount: page.totalCount,
        hasMore: page.entries.length < page.totalCount,
        errorMessage: '',
      ));
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _fail(error);
    }
  }

  void _scheduleRefresh() {
    if (_disposed) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(eventRefreshDelay, () {
      _refreshTimer = null;
      unawaited(_reloadFirstPage());
    });
  }

  void _setBusy(String? id, bool busy) {
    if (id == null || _disposed) return;
    final ids = Set<String>.from(_state.busySectionIds);
    if (busy) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    _setState(_state.copyWith(busySectionIds: ids));
  }

  void _fail(Object error) {
    _setState(_state.copyWith(
      status: SectionControlViewStatus.failed,
      errorMessage: resourceStudioUserMessage(error),
      error: asAppDomainError(error),
    ));
  }

  void _setState(SectionControlViewState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    unawaited(_eventsSubscription?.cancel());
    _eventsSubscription = null;
    super.dispose();
  }
}
