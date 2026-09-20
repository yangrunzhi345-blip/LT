import 'package:flutter/foundation.dart';

import '../domain/resources/resource_blueprint.dart';
import '../domain/resources/resource_contracts.dart';
import '../services/llm_service.dart';
import '../application/llm/llm_gateway.dart';
import '../application/resources/resource_blueprint_repository.dart';
import '../application/resources/resource_creation_contracts.dart';
import '../application/resource_library/import_models.dart';
import '../application/resource_library/import_use_cases.dart';
import '../models/resource_library_mode.dart';

enum ResourceImportPhase { idle, generating, reviewing, saving }

class ResourceLibraryImportController extends ChangeNotifier {
  final ImportConversationCharacterUseCase conversationCharacterUseCase;
  final ImportWorldviewUseCase worldviewUseCase;
  final Future<void> Function()? onWorldviewSaved;

  ResourceImportPhase phase = ResourceImportPhase.idle;
  ConversationCharacterDraft? characterDraft;
  WorldviewImportDraft? worldviewDraft;
  WorldviewGenerationProgress? worldviewProgress;
  WorldviewImportRequest? _worldviewRequest;
  Object? error;
  bool _disposed = false;
  int _generation = 0;

  ResourceLibraryImportController({
    required this.conversationCharacterUseCase,
    required this.worldviewUseCase,
    this.onWorldviewSaved,
  });

  String? get errorMessage {
    final value = error;
    if (value == null) return null;
    if (value is ImportValidationException) return value.message;
    if (value is FormatException) return 'AI 输出解析失败：${value.message}';
    final str = value.toString();
    if (str.contains('SocketException') || str.contains('TimeoutException')) {
      return '网络请求超时或连接失败，请检查网络后重试';
    }
    return '生成失败：$value';
  }

  void reset() {
    _generation++;
    phase = ResourceImportPhase.idle;
    characterDraft = null;
    worldviewDraft = null;
    worldviewProgress = null;
    _worldviewRequest = null;
    error = null;
    _notify();
  }

  void setConversationCharacterDraft(ConversationCharacterDraft draft) {
    characterDraft = draft;
    phase = ResourceImportPhase.reviewing;
    error = null;
    _notify();
  }

  Future<void> generateConversationCharacter(
    ConversationCharacterImportRequest request,
  ) async {
    final generation = ++_generation;
    phase = ResourceImportPhase.generating;
    error = null;
    _notify();
    try {
      final draft = await conversationCharacterUseCase.generate(request);
      if (!_isCurrent(generation)) return;
      characterDraft = draft;
      phase = ResourceImportPhase.reviewing;
    } catch (exception) {
      if (!_isCurrent(generation)) return;
      error = exception;
      phase = ResourceImportPhase.idle;
    }
    _notify();
  }

  Future<void> generateWorldview(WorldviewImportRequest request) async {
    final generation = ++_generation;
    _worldviewRequest = request;
    worldviewProgress = null;
    phase = ResourceImportPhase.generating;
    error = null;
    _notify();
    try {
      final draft = await worldviewUseCase.generate(
        request,
        onProgress: (progress) {
          if (!_isCurrent(generation)) return;
          worldviewProgress = progress;
          _notify();
        },
      );
      if (!_isCurrent(generation)) return;
      worldviewDraft = draft;
      phase = ResourceImportPhase.reviewing;
    } catch (exception) {
      if (!_isCurrent(generation)) return;
      error = exception;
      phase = ResourceImportPhase.idle;
    }
    _notify();
  }

  Future<void> planWorldview(WorldviewImportRequest request) async {
    final generation = ++_generation;
    phase = ResourceImportPhase.generating;
    error = null;
    _notify();
    try {
      await worldviewUseCase.plan(request);
      // Planning is not generation completion. Production callers continue in
      // Resource Studio; this compatibility entry point returns to idle until
      // a persisted GenerationSession can be observed.
      if (_isCurrent(generation)) phase = ResourceImportPhase.idle;
    } catch (exception) {
      if (!_isCurrent(generation)) return;
      error = exception;
      phase = ResourceImportPhase.idle;
    }
    _notify();
  }

  Future<void> saveConversationCharacter({String? id}) async {
    final draft = characterDraft;
    if (draft == null) return;
    await _save(() => conversationCharacterUseCase.save(draft, id: id));
  }

  Future<void> saveWorldview({
    String? id,
    ResourceLibraryMode? mode,
  }) async {
    final draft = worldviewDraft;
    if (draft == null) return;
    await _save(() async {
      await worldviewUseCase.save(
        draft,
        id: id,
        mode: mode ??
            _worldviewRequest?.libraryMode ??
            ResourceLibraryMode.adventure,
      );
      await onWorldviewSaved?.call();
    });
  }

  Future<void> _save(Future<void> Function() action) async {
    final generation = _generation;
    phase = ResourceImportPhase.saving;
    error = null;
    _notify();
    try {
      await action();
      if (!_isCurrent(generation)) return;
      phase = ResourceImportPhase.reviewing;
    } catch (exception) {
      if (!_isCurrent(generation)) return;
      error = exception;
      phase = ResourceImportPhase.reviewing;
    }
    _notify();
  }

  void retry() {
    if (error != null) {
      phase = ResourceImportPhase.idle;
      error = null;
      _notify();
    }
  }

  /// Retrieves pending worldview planning sessions waiting for blueprint planning.
  Future<List<ResourceCreationSession>> pendingPlanningSessions() {
    return worldviewUseCase.pendingPlanningSessions();
  }

  /// Plans an adaptive blueprint for an initiated worldview session.
  Future<ResourceBlueprint> planWorldviewBlueprint(
    String sessionId, {
    GenerationTaskHandle? taskHandle,
    Duration timeout = const Duration(seconds: 60),
    BlueprintIdPool? idPool,
  }) {
    return worldviewUseCase.planBlueprint(
      sessionId,
      taskHandle: taskHandle,
      timeout: timeout,
      idPool: idPool,
    );
  }

  /// Confirms a planned worldview blueprint.
  Future<ResourceBlueprintConfirmResult> confirmWorldviewBlueprint(
    String blueprintId, {
    String? nameOverride,
    ResourceId? explicitResourceId,
  }) {
    return worldviewUseCase.confirmBlueprint(
      blueprintId,
      nameOverride: nameOverride,
      explicitResourceId: explicitResourceId,
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
