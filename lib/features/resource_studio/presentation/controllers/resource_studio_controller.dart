import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/config/generation_limits.dart';
import '../../../../core/debug/generation_diagnostics.dart';
import '../../../../domain/resources/resource_contracts.dart';
import '../../../../application/resources/resource_creation_contracts.dart';
import '../../../../domain/resources/resource_generation_patch.dart';
import '../../../../domain/resources/streaming_generation_runtime_contracts.dart';
import '../../application/use_cases/resource_studio_runtime.dart';
import '../../domain/models/resource_studio_state.dart';
import '../resource_studio_user_message.dart';

/// View-model translating runtime events into immutable Studio state.
final class ResourceStudioController extends ChangeNotifier {
  ResourceStudioController({
    required ResourceStudioRuntime runtime,
    String? resourceId,
    String? sessionId,
  })  : _runtime = runtime,
        _resourceId = resourceId == null ? null : ResourceId(resourceId),
        _sessionId = sessionId {
    // Expose Studio transient state to the generation watchdog dump (P0).
    GenerationDiagnostics.instance.registerSnapshotProvider(
      'studioController',
      () => <String, Object?>{
        'status': _state.status.name,
        'buffers': _buffers.length,
        'dirtyParts': _dirtyPartIds.length,
        'previewNotifiers': _partPreviewNotifiers.length,
        'patchFlushTimerActive': _patchFlushTimer != null,
      },
    );
  }

  final ResourceStudioRuntime _runtime;
  final ResourceId? _resourceId;
  final String? _sessionId;
  final Map<String, StringBuffer> _buffers = {};
  final Map<String, ValueNotifier<String>> _partPreviewNotifiers = {};

  /// The attempt currently owning each Part, so a late failure event from a
  /// superseded attempt can never be applied to the current one.
  final Map<String, String> _currentAttemptByPart = <String, String>{};

  /// Parts that already committed successfully in this session. A failure
  /// event arriving for one of them is stale by definition.
  final Set<String> _completedPartIds = <String>{};

  /// The Part the currently displayed error belongs to, or null when the
  /// banner is not Part-scoped. Lets a new attempt / a successful retry clear
  /// exactly its own error instead of clobbering another Part's failure.
  String? _errorPartId;

  StreamSubscription<GenerationRuntimeEvent>? _eventsSubscription;
  Timer? _patchFlushTimer;
  final Set<String> _dirtyPartIds = <String>{};
  int _previewMaterializationCount = 0;
  ResourceStudioState _state = const ResourceStudioState.initial();
  bool _disposed = false;

  /// Monotonic token shared by [load] and [_refreshSession]. A late completion
  /// of an earlier load/refresh (or its error) must never publish over a newer
  /// request's state, so every publish re-validates the token first.
  int _stateGeneration = 0;

  ResourceStudioState get state => _state;

  /// Returns the transient preview notifier for [partId].
  ///
  /// Runtime and persisted state remain the business authority. This notifier
  /// only lets a Part repaint without rebuilding the Studio shell.
  ValueListenable<String> partPreview(PartId partId) =>
      _partPreviewNotifiers.putIfAbsent(
        partId.value,
        () => ValueNotifier<String>(_state.partContents[partId.value] ?? ''),
      );

  /// Number of preview string materializations, exposed for performance tests.
  @visibleForTesting
  int get previewMaterializationCount => _previewMaterializationCount;

  /// Test/observability seam: transient streaming buffers not yet released.
  @visibleForTesting
  int get bufferCount => _buffers.length;

  /// Test/observability seam: Parts waiting for the next throttled flush.
  @visibleForTesting
  int get dirtyPartCount => _dirtyPartIds.length;

  /// Test/observability seam: whether a preview flush timer is pending.
  @visibleForTesting
  bool get isPatchFlushTimerActive => _patchFlushTimer != null;

  /// Test/observability seam: live preview notifiers (bounded by Part count).
  @visibleForTesting
  int get previewNotifierCount => _partPreviewNotifiers.length;

  Future<void> load() async {
    final generation = ++_stateGeneration;
    _setState(_state.copyWith(status: ResourceStudioStatus.loading));
    try {
      final sessionId = _sessionId;
      final resourceId = _resourceId;
      var session = sessionId == null
          ? (resourceId == null
              ? null
              : await _runtime.getLatestSessionForResource(resourceId.value))
          : await _runtime.getSession(sessionId);
      final resolvedResourceId = session?.resourceId ?? resourceId;
      if (session == null && resolvedResourceId != null) {
        session = await _runtime.ensureSession(resolvedResourceId);
      }
      final tree = resolvedResourceId == null
          ? null
          : await _runtime.readTree(resolvedResourceId);
      if (_disposed || generation != _stateGeneration) return;
      // A fresh load re-derives state from persistence, so any Part-scoped
      // banner ownership from the previous view is dropped with it.
      _errorPartId = null;
      _setState(_state.copyWith(
        status: _statusForSession(session),
        resourceId: resolvedResourceId,
        session: session,
        tree: tree,
        partContents: _initialPartContents(tree),
        errorMessage: '',
      ));
      _syncPartPreviewNotifiers();
      _eventsSubscription ??= _runtime.events.listen(_handleEvent);
    } catch (error) {
      if (_disposed || generation != _stateGeneration) return;
      _setState(_state.copyWith(
        status: ResourceStudioStatus.failed,
        errorMessage: '',
        error: resourceStudioError(error),
      ));
    }
  }

  Future<List<StreamingGenerationSession>> activeSessions() =>
      _runtime.findActiveSessions();

  Future<List<ResourceCreationSession>> pendingPlanningSessions() =>
      _runtime.pendingPlanningSessions();

  Future<List<Resource>> listResources() => _runtime.listResources();

  Future<void> start() => _runCommand(
        () async {
          final session = _state.session;
          if (session == null) throw StateError('没有可启动的生成会话');
          await _runtime.start(session.sessionId);
        },
      );

  Future<void> pause() => _runCommand(() async {
        final session = _state.session;
        if (session == null) throw StateError('没有可暂停的生成会话');
        await _runtime.pause(session.sessionId);
      });

  Future<void> resume() => _runCommand(() async {
        final session = _state.session;
        if (session == null) throw StateError('没有可恢复的生成会话');
        await _runtime.resume(session.sessionId);
      });

  Future<void> cancel() => _runCommand(() async {
        final session = _state.session;
        if (session == null) throw StateError('没有可取消的生成会话');
        await _runtime.cancel(session.sessionId);
      });

  Future<void> retry() => _runCommand(() async {
        final session = _state.session;
        if (session == null) throw StateError('没有可重试的生成会话');
        await _runtime.resume(session.sessionId);
      }, status: ResourceStudioStatus.retrying);

  Future<void> recover() => _runCommand(() async {
        final session = _state.session;
        if (session == null) throw StateError('没有可恢复的生成会话');
        await _runtime.recover(session.sessionId);
      });

  Future<void> createAndStart({
    required ResourceType resourceType,
    required String name,
    required ReferenceSource referenceSource,
    required int targetCharacters,
    String origin = 'resource-studio',
    String libraryMode = 'adventure',
    String? idempotencyKey,
    ResourceId? targetResourceId,
    String originWorldviewId = '',
  }) =>
      _runCommand(() async {
        final session = await _runtime.createAndStart(
          resourceType: resourceType,
          name: name,
          referenceSource: referenceSource,
          targetCharacters: targetCharacters,
          origin: origin,
          libraryMode: libraryMode,
          idempotencyKey: idempotencyKey,
          targetResourceId: targetResourceId,
          originWorldviewId: originWorldviewId,
        );
        final tree = await _runtime.readTree(session.resourceId);
        _errorPartId = null;
        _setState(_state.copyWith(
          status: ResourceStudioStatus.generating,
          resourceId: session.resourceId,
          session: session,
          tree: tree,
          partContents: _initialPartContents(tree),
          errorMessage: '',
        ));
        _syncPartPreviewNotifiers();
      });

  void selectPart(PartId partId) {
    if (_state.selectedPartId == partId) return;
    _setState(_state.copyWith(selectedPartId: partId));
  }

  void _handleEvent(GenerationRuntimeEvent event) {
    if (_disposed ||
        (_state.session != null &&
            event.generationId != _state.session!.sessionId)) {
      return;
    }
    final session = _state.session;
    if (session == null && _resourceId != event.resourceId) return;
    var partContents = Map<String, String>.from(_state.partContents);
    var status = _state.status;
    var errorMessage = _state.errorMessage;
    PartId? selectedPartId = _state.selectedPartId;
    var refreshSession = false;
    if (event is GenerationStarted) {
      status = ResourceStudioStatus.generating;
      refreshSession = true;
    } else if (event is PartStarted) {
      selectedPartId = event.partId;
      status = ResourceStudioStatus.generating;
      _buffers[event.partId.value] = StringBuffer();
      _currentAttemptByPart[event.partId.value] = event.attemptId;
      // A new attempt supersedes the previous attempt of THIS Part, including
      // its temporary error. The failure itself is not lost: it stays in the
      // attempt rows as history, and only the live banner is cleared.
      if (_errorPartId == event.partId.value) {
        errorMessage = '';
        _errorPartId = null;
      }
      refreshSession = true;
    } else if (event is PartPreviewUpdated) {
      selectedPartId = event.partId;
      status = ResourceStudioStatus.generating;
      _applyPreviewSnapshot(event.partId, event.accumulatedContent);
      if (selectedPartId != _state.selectedPartId || status != _state.status) {
        _setState(_state.copyWith(
          status: status,
          selectedPartId: selectedPartId,
        ));
      }
      return;
    } else if (event is PatchReceived) {
      selectedPartId = event.partId;
      status = ResourceStudioStatus.generating;
      _appendPatch(event.partId, event.patch);
      if (selectedPartId != _state.selectedPartId || status != _state.status) {
        _setState(_state.copyWith(
          status: status,
          selectedPartId: selectedPartId,
        ));
      }
      return;
    } else if (event is ValidationStarted) {
      status = ResourceStudioStatus.validating;
      refreshSession = true;
    } else if (event is ValidationFailed) {
      // Stale-event guard (P0 residual-state fix): a failure only describes
      // the attempt that produced it. If the Studio already moved on — a newer
      // attempt started, or the Part committed — applying it would resurrect
      // an error the run has already recovered from.
      if (_isStaleFailure(event.partId, event.attemptId)) {
        return;
      }
      status = ResourceStudioStatus.failed;
      final typedError = event.error ?? resourceStudioError(event.errorMessage);
      _errorPartId = event.partId.value;
      final contents = _discardUncommittedPart(event.partId);
      _setState(_state.copyWith(
        status: status,
        selectedPartId: selectedPartId,
        partContents: contents,
        errorMessage: '',
        error: typedError,
      ));
      _syncPartPreviewNotifiers();
      unawaited(_refreshSession());
      return;
    } else if (event is PartCompleted) {
      _materializePartPreview(event.partId.value);
      _buffers.remove(event.partId.value);
      _dirtyPartIds.remove(event.partId.value);
      _completedPartIds.add(event.partId.value);
      _currentAttemptByPart.remove(event.partId.value);
      // A recovered Part must not keep its earlier failure on screen.
      if (_errorPartId == event.partId.value) {
        errorMessage = '';
        _errorPartId = null;
      }
      partContents = Map<String, String>.from(_state.partContents);
      status = ResourceStudioStatus.generating;
      refreshSession = true;
    } else if (event is GenerationCompleted) {
      _flushPendingPatches();
      partContents = Map<String, String>.from(_state.partContents);
      status = ResourceStudioStatus.completed;
      // Terminal success owns the banner: whatever failed and was recovered
      // along the way must not remain visible as the current error.
      errorMessage = '';
      _errorPartId = null;
      refreshSession = false;
    } else if (event is GenerationFailed) {
      status = ResourceStudioStatus.failed;
      final typedError = event.error ?? resourceStudioError(event.errorMessage);
      _errorPartId = event.failedPartId?.value;
      final contents = _discardAllUncommittedParts();
      _setState(_state.copyWith(
        status: status,
        selectedPartId: event.failedPartId ?? selectedPartId,
        partContents: contents,
        errorMessage: '',
        error: typedError,
      ));
      _syncPartPreviewNotifiers();
      unawaited(_refreshSession());
      return;
    }
    _setState(_state.copyWith(
      status: status,
      selectedPartId: selectedPartId,
      partContents: partContents,
      errorMessage: errorMessage,
      clearError: event is GenerationCompleted || event is PartStarted,
    ));
    if (event is GenerationCompleted) {
      unawaited(_refreshCommittedTree(event.resourceId));
    } else if (refreshSession) {
      unawaited(_refreshSession());
    }
  }

  /// Whether [attemptId]'s failure describes a Part state the Studio has
  /// already moved past.
  ///
  /// Falls back to false when no attempt is tracked (a Studio opened mid-flight must
  /// still show a real failure), true once the Part committed or once a newer
  /// attempt was started for it.
  bool _isStaleFailure(PartId partId, String attemptId) {
    if (_completedPartIds.contains(partId.value)) return true;
    final knownAttempt = _currentAttemptByPart[partId.value];
    if (knownAttempt == null) return false;
    return knownAttempt != attemptId;
  }

  void _appendPatch(
    PartId partId,
    ResourceGenerationPatch patch,
  ) {
    final buffer = _buffers.putIfAbsent(partId.value, StringBuffer.new);
    if (patch.op == ResourcePatchOp.startPart ||
        patch.op == ResourcePatchOp.appendText) {
      buffer.write(patch.textDelta);
      _dirtyPartIds.add(partId.value);
      _schedulePatchFlush();
    }
  }

  /// Replaces a Part's transient preview with a full runtime snapshot
  /// ([PartPreviewUpdated]). The snapshot already went through the runtime's
  /// protocol accumulator, so it is applied verbatim; the Studio-side flush
  /// timer keeps throttling the actual notifier materialization.
  void _applyPreviewSnapshot(PartId partId, String content) {
    final buffer = _buffers.putIfAbsent(partId.value, StringBuffer.new);
    buffer
      ..clear()
      ..write(content);
    _dirtyPartIds.add(partId.value);
    _schedulePatchFlush();
  }

  void _schedulePatchFlush() {
    if (_patchFlushTimer != null || _disposed) return;
    _patchFlushTimer = Timer(GenerationLimits.streamingPreviewThrottle, () {
      _patchFlushTimer = null;
      _flushPendingPatches();
    });
  }

  void _flushPendingPatches() {
    if (_dirtyPartIds.isEmpty || _disposed) return;
    final dirtyPartIds = List<String>.of(_dirtyPartIds);
    for (final partId in dirtyPartIds) {
      _materializePartPreview(partId);
    }
    _dirtyPartIds.clear();
  }

  void _materializePartPreview(String partId) {
    final content = _buffers[partId]?.toString();
    if (content == null) return;
    _previewMaterializationCount++;
    final contents = Map<String, String>.from(_state.partContents)
      ..[partId] = content;
    _state = _state.copyWith(partContents: contents);
    _setPartPreview(partId, content);
  }

  /// Removes transient output for a Part that did not pass validation and was
  /// therefore never committed by the runtime. The Studio must not present an
  /// in-memory preview as persisted content after a failed generation.
  Map<String, String> _discardUncommittedPart(PartId partId) {
    _buffers.remove(partId.value);
    _dirtyPartIds.remove(partId.value);
    final contents = Map<String, String>.from(_state.partContents);
    _restorePersistedPartContent(contents, partId);
    return contents;
  }

  void _restorePersistedPartContent(
    Map<String, String> contents,
    PartId partId,
  ) {
    final persistedContent = _initialPartContents(_state.tree)[partId.value];
    if (persistedContent == null) {
      contents.remove(partId.value);
    } else {
      contents[partId.value] = persistedContent;
    }
  }

  /// Discards every active preview after a terminal runtime failure. Completed
  /// parts leave [_buffers] at [PartCompleted], so only uncommitted buffers are
  /// removed here.
  Map<String, String> _discardAllUncommittedParts() {
    final pendingPartIds = <String>{
      ..._buffers.keys,
      ..._dirtyPartIds,
    };
    var contents = Map<String, String>.from(_state.partContents);
    for (final partId in pendingPartIds) {
      _buffers.remove(partId);
      _dirtyPartIds.remove(partId);
      _restorePersistedPartContent(contents, PartId(partId));
    }
    return contents;
  }

  Future<void> _refreshSession() async {
    final sessionId = _state.session?.sessionId;
    if (sessionId == null || _disposed) return;
    final generation = ++_stateGeneration;
    final session = await _runtime.getSession(sessionId);
    if (session == null ||
        _disposed ||
        // A newer refresh (or load) already superseded this one; publishing
        // the stale snapshot would roll the visible state backwards.
        generation != _stateGeneration) {
      return;
    }
    _setState(_state.copyWith(session: session));
  }

  /// Reconciles the visible tree from the committed repository after the
  /// Runtime reports terminal success. Streaming buffers are previews and must
  /// not become the Outline's persisted-content authority.
  Future<void> _refreshCommittedTree(ResourceId resourceId) async {
    final sessionId = _state.session?.sessionId;
    if (sessionId == null || _disposed) return;
    final generation = ++_stateGeneration;
    final tree = await _runtime.readTree(resourceId);
    final session = await _runtime.getSession(sessionId);
    if (tree == null ||
        session == null ||
        _disposed ||
        generation != _stateGeneration) {
      return;
    }
    _setState(_state.copyWith(
      tree: tree,
      session: session,
      partContents: _initialPartContents(tree),
    ));
    _syncPartPreviewNotifiers();
  }

  /// Reentrancy guard for [start]/[pause]/[resume]/[cancel]/[retry]/
  /// [recover]/[createAndStart]: a second command while one is still active is
  /// rejected instead of racing it. Widget-level button disabling is UX only;
  /// this is the actual concurrency boundary (createAndStart especially must
  /// never run twice and produce two resources).
  bool _commandInFlight = false;

  Future<void> _runCommand(
    Future<void> Function() command, {
    ResourceStudioStatus status = ResourceStudioStatus.generating,
  }) async {
    if (_commandInFlight || _disposed) return;
    _commandInFlight = true;
    _setState(_state.copyWith(status: status, errorMessage: ''));
    try {
      await command();
      await _refreshSession();
    } catch (error) {
      _setState(_state.copyWith(
        status: ResourceStudioStatus.failed,
        errorMessage: '',
        error: resourceStudioError(error),
      ));
    } finally {
      _commandInFlight = false;
    }
  }

  ResourceStudioStatus _statusForSession(StreamingGenerationSession? session) {
    if (session == null) return ResourceStudioStatus.ready;
    return switch (session.status) {
      StreamingLifecycleStatus.completed => ResourceStudioStatus.completed,
      StreamingLifecycleStatus.paused => ResourceStudioStatus.paused,
      StreamingLifecycleStatus.failed ||
      StreamingLifecycleStatus.cancelled =>
        ResourceStudioStatus.failed,
      StreamingLifecycleStatus.validating => ResourceStudioStatus.validating,
      StreamingLifecycleStatus.generatingPart ||
      StreamingLifecycleStatus.receivingPatch ||
      StreamingLifecycleStatus.committing =>
        ResourceStudioStatus.generating,
      _ => ResourceStudioStatus.ready,
    };
  }

  Map<String, String> _initialPartContents(ResourceTree? tree) => {
        for (final part in tree?.parts ?? const <ResourcePart>[])
          part.id.value: part.content,
      };

  void _syncPartPreviewNotifiers() {
    for (final entry in _state.partContents.entries) {
      _setPartPreview(entry.key, entry.value);
    }
  }

  void _setPartPreview(String partId, String content) {
    final notifier = _partPreviewNotifiers[partId];
    if (notifier != null && notifier.value != content) {
      notifier.value = content;
    }
  }

  void _setState(ResourceStudioState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    GenerationDiagnostics.instance
        .unregisterSnapshotProvider('studioController');
    _patchFlushTimer?.cancel();
    _patchFlushTimer = null;
    _dirtyPartIds.clear();
    for (final notifier in _partPreviewNotifiers.values) {
      notifier.dispose();
    }
    _partPreviewNotifiers.clear();
    unawaited(_eventsSubscription?.cancel());
    super.dispose();
  }
}
