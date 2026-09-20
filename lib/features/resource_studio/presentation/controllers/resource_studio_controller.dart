import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/config/generation_limits.dart';
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
        _sessionId = sessionId;

  final ResourceStudioRuntime _runtime;
  final ResourceId? _resourceId;
  final String? _sessionId;
  final Map<String, StringBuffer> _buffers = {};
  StreamSubscription<GenerationRuntimeEvent>? _eventsSubscription;
  Timer? _patchFlushTimer;
  final Map<String, String> _pendingPartContents = {};
  ResourceStudioState _state = const ResourceStudioState.initial();
  bool _disposed = false;

  /// Monotonic token shared by [load] and [_refreshSession]. A late completion
  /// of an earlier load/refresh (or its error) must never publish over a newer
  /// request's state, so every publish re-validates the token first.
  int _stateGeneration = 0;

  ResourceStudioState get state => _state;

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
      _setState(_state.copyWith(
        status: _statusForSession(session),
        resourceId: resolvedResourceId,
        session: session,
        tree: tree,
        partContents: _initialPartContents(tree),
        errorMessage: '',
      ));
      _eventsSubscription ??= _runtime.events.listen(_handleEvent);
    } catch (error) {
      if (_disposed || generation != _stateGeneration) return;
      _setState(_state.copyWith(
        status: ResourceStudioStatus.failed,
        errorMessage: _message(error),
      ));
    }
  }

  Future<List<StreamingGenerationSession>> activeSessions() =>
      _runtime.findActiveSessions();

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
  }) =>
      _runCommand(() async {
        final session = await _runtime.createAndStart(
          resourceType: resourceType,
          name: name,
          referenceSource: referenceSource,
          targetCharacters: targetCharacters,
        );
        final tree = await _runtime.readTree(session.resourceId);
        _setState(_state.copyWith(
          status: ResourceStudioStatus.generating,
          resourceId: session.resourceId,
          session: session,
          tree: tree,
          partContents: _initialPartContents(tree),
          errorMessage: '',
        ));
      });

  void selectPart(PartId partId) {
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
    final partContents = Map<String, String>.from(_state.partContents);
    var status = _state.status;
    PartId? selectedPartId = _state.selectedPartId;
    if (event is GenerationStarted) {
      status = ResourceStudioStatus.generating;
    } else if (event is PartStarted) {
      selectedPartId = event.partId;
      status = ResourceStudioStatus.generating;
      _buffers[event.partId.value] = StringBuffer();
    } else if (event is PatchReceived) {
      selectedPartId = event.partId;
      status = ResourceStudioStatus.generating;
      _appendPatch(event.partId, event.patch);
    } else if (event is ValidationStarted) {
      status = ResourceStudioStatus.validating;
    } else if (event is ValidationFailed) {
      status = ResourceStudioStatus.failed;
      _setState(_state.copyWith(
        status: status,
        selectedPartId: selectedPartId,
        partContents: _discardUncommittedPart(event.partId),
        errorMessage: resourceStudioUserMessage(event.errorMessage),
      ));
      return;
    } else if (event is PartCompleted) {
      final committedContent = _buffers.remove(event.partId.value)?.toString();
      _pendingPartContents.remove(event.partId.value);
      if (committedContent != null) {
        partContents[event.partId.value] = committedContent;
      }
      status = ResourceStudioStatus.generating;
    } else if (event is GenerationCompleted) {
      _flushPendingPatches();
      partContents.addAll(_pendingPartContents);
      status = ResourceStudioStatus.completed;
    } else if (event is GenerationFailed) {
      status = ResourceStudioStatus.failed;
      _setState(_state.copyWith(
        status: status,
        selectedPartId: event.failedPartId ?? selectedPartId,
        partContents: _discardAllUncommittedParts(),
        errorMessage: resourceStudioUserMessage(event.errorMessage),
      ));
      return;
    }
    _setState(_state.copyWith(
      status: status,
      selectedPartId: selectedPartId,
      partContents: partContents,
    ));
    unawaited(_refreshSession());
  }

  void _appendPatch(
    PartId partId,
    ResourceGenerationPatch patch,
  ) {
    final buffer = _buffers.putIfAbsent(partId.value, StringBuffer.new);
    if (patch.op == ResourcePatchOp.startPart ||
        patch.op == ResourcePatchOp.appendText) {
      buffer.write(patch.textDelta);
      _pendingPartContents[partId.value] = buffer.toString();
      _schedulePatchFlush();
    }
  }

  void _schedulePatchFlush() {
    if (_patchFlushTimer != null || _disposed) return;
    _patchFlushTimer = Timer(GenerationLimits.streamingUiTick, () {
      _patchFlushTimer = null;
      _flushPendingPatches();
    });
  }

  void _flushPendingPatches() {
    if (_pendingPartContents.isEmpty || _disposed) return;
    final contents = Map<String, String>.from(_state.partContents)
      ..addAll(_pendingPartContents);
    _pendingPartContents.clear();
    _setState(_state.copyWith(partContents: contents));
  }

  /// Removes transient output for a Part that did not pass validation and was
  /// therefore never committed by the runtime. The Studio must not present an
  /// in-memory preview as persisted content after a failed generation.
  Map<String, String> _discardUncommittedPart(PartId partId) {
    _buffers.remove(partId.value);
    _pendingPartContents.remove(partId.value);
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
      ..._pendingPartContents.keys,
    };
    var contents = Map<String, String>.from(_state.partContents);
    for (final partId in pendingPartIds) {
      _buffers.remove(partId);
      _pendingPartContents.remove(partId);
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
        errorMessage: _message(error),
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

  String _message(Object error) => resourceStudioUserMessage(error);

  void _setState(ResourceStudioState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _patchFlushTimer?.cancel();
    _patchFlushTimer = null;
    _pendingPartContents.clear();
    unawaited(_eventsSubscription?.cancel());
    super.dispose();
  }
}
