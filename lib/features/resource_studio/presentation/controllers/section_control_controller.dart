import 'dart:async';

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

  SectionControlViewState get state => _state;

  /// Starts (or restarts) tracking one resource's sections.
  Future<void> load(ResourceId resourceId) async {
    if (_disposed) return;
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

    final offset = _state.entries.length;
    _setState(_state.copyWith(status: SectionControlViewStatus.working));
    try {
      final page = await _runtime.listSections(
        resourceId: resourceId,
        limit: pageSize,
        offset: offset,
      );
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
        successMessage: (result) => result is SectionValidationResult
            ? (result.isValid
                ? '「${entry.title}」校验通过'
                : '「${entry.title}」校验未通过：${result.issues.length} 项问题')
            : '校验完成',
      );

  Future<bool> regenerateSection(SectionControlEntry entry) => _run(
        (_) => _runtime.regenerateSection(id: entry.id),
        busyId: entry.id.value,
        successMessage: (result) => result is SectionGenerationOutcome
            ? (result.success
                ? '「${entry.title}」已重新生成 '
                    '${result.completedPartCount}/${result.partCount} Part'
                : '「${entry.title}」生成中止：${result.errorMessage}')
            : '生成完成',
      );

  /// Runs one section operation, then refreshes from persisted state.
  Future<bool> _run(
    Future<Object?> Function(ResourceId resourceId) action, {
    required String? busyId,
    String Function(Object? result)? successMessage,
  }) async {
    final resourceId = _state.resourceId;
    if (_disposed || resourceId == null) return false;

    _setBusy(busyId, true);
    try {
      final result = await action(resourceId);
      await _reloadFirstPage();
      _setState(_state.copyWith(
        lastMessage: successMessage?.call(result) ?? '',
        errorMessage: '',
      ));
      return true;
    } catch (error) {
      _fail(error);
      return false;
    } finally {
      _setBusy(busyId, false);
    }
  }

  Future<void> _reloadFirstPage() async {
    final resourceId = _state.resourceId;
    if (_disposed || resourceId == null) return;
    try {
      final page = await _runtime.listSections(
        resourceId: resourceId,
        limit: pageSize,
        offset: 0,
      );
      _setState(_state.copyWith(
        status: SectionControlViewStatus.ready,
        entries: page.entries,
        totalCount: page.totalCount,
        hasMore: page.entries.length < page.totalCount,
        errorMessage: '',
      ));
    } catch (error) {
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
      errorMessage: error.toString().replaceFirst('Bad state: ', ''),
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
