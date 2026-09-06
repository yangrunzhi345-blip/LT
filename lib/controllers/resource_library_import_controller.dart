import 'package:flutter/foundation.dart';

import '../application/llm/llm_gateway.dart';
import '../application/resource_library/import_models.dart';
import '../application/resource_library/import_use_cases.dart';
import '../models/resource_library_mode.dart';

enum ResourceImportPhase {
  idle,
  generating,
  reviewing,
  saving,
  completed,
  failed
}

class ResourceLibraryImportController extends ChangeNotifier {
  final ImportConversationCharacterUseCase conversationCharacterUseCase;
  final ImportWorldviewUseCase worldviewUseCase;
  final Future<void> Function()? onWorldviewSaved;

  ResourceImportPhase phase = ResourceImportPhase.idle;
  ConversationCharacterDraft? characterDraft;
  WorldviewImportDraft? worldviewDraft;
  WorldviewGenerationProgress? worldviewProgress;
  WorldviewImportRequest? _worldviewRequest;
  bool _worldviewRunInBackground = false;
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
    _worldviewRunInBackground = false;
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
      phase = ResourceImportPhase.failed;
    }
    _notify();
  }

  Future<void> generateWorldview(
    WorldviewImportRequest request, {
    bool runInBackground = false,
  }) async {
    final generation = ++_generation;
    _worldviewRequest = request;
    _worldviewRunInBackground = runInBackground;
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
      if (_worldviewRunInBackground) {
        phase = ResourceImportPhase.saving;
        _notify();
        await worldviewUseCase.save(
          draft,
          mode: request.libraryMode,
        );
        await onWorldviewSaved?.call();
        if (!_isCurrent(generation)) return;
        phase = ResourceImportPhase.completed;
      } else {
        phase = ResourceImportPhase.reviewing;
      }
    } catch (exception) {
      if (!_isCurrent(generation)) return;
      error = exception;
      phase = ResourceImportPhase.failed;
    }
    _notify();
  }

  void detachWorldviewToBackground() {
    if (phase == ResourceImportPhase.generating) {
      _worldviewRunInBackground = true;
    }
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
      phase = ResourceImportPhase.completed;
    } catch (exception) {
      if (!_isCurrent(generation)) return;
      error = exception;
      phase = ResourceImportPhase.failed;
    }
    _notify();
  }

  void retry() {
    if (phase == ResourceImportPhase.failed) {
      phase = ResourceImportPhase.idle;
      error = null;
      _notify();
    }
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
