import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../application/resource_library/import_models.dart';
import '../application/resource_library/import_use_cases.dart';
import '../models/resource_library_mode.dart';

enum ResourceCardImportPhase {
  idle,
  generating,
  reviewing,
  saving,
  completed,
  failed
}

class ResourceCardImportController extends ChangeNotifier {
  final ResourceCardImportUseCase useCase;

  ResourceCardImportPhase phase = ResourceCardImportPhase.idle;
  ResourceCardImportDraft? draft;
  Object? error;
  String? progressStage;
  bool _disposed = false;
  int _generation = 0;

  ResourceCardImportController({required this.useCase});

  /// 选中关联角色的完整字段上下文。解码下沉，页面不再解析 json_data。
  List<Map<String, String>> associatedCharactersFor({
    required List<Map<String, dynamic>> cards,
    required Set<String> selectedIds,
  }) {
    return cards
        .where((card) => selectedIds.contains(card['id']?.toString()))
        .map((card) {
      Map<String, dynamic> data = {};
      try {
        final decoded = jsonDecode(card['json_data']?.toString() ?? '{}');
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      } catch (_) {}
      return <String, String>{
        'name': data['name']?.toString() ?? card['name']?.toString() ?? '',
        'gender': data['gender']?.toString() ?? '',
        'profession': data['profession']?.toString() ?? '',
        'personality': data['personality']?.toString() ?? '',
        'background': data['background']?.toString() ??
            data['description']?.toString() ??
            '',
        'appearance': data['appearance']?.toString() ?? '',
      };
    }).toList(growable: false);
  }

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

  bool _runInBackground = false;

  Future<void> generate(ResourceCardImportRequest request,
      {bool runInBackground = false}) async {
    final generation = ++_generation;
    _runInBackground = runInBackground;
    phase = ResourceCardImportPhase.generating;
    draft = null;
    error = null;
    progressStage = null;
    _notify();
    try {
      final result = await useCase.generate(
        request,
        onProgress: (current, total, stage) {
          if (!_isCurrent(generation)) return;
          progressStage = '[$current/$total] $stage';
          _notify();
        },
      );
      if (!_isCurrent(generation)) return;
      draft = result;
      if (_runInBackground) {
        // Auto-save after generation
        phase = ResourceCardImportPhase.saving;
        _notify();
        await useCase.save(draft!, mode: request.libraryMode);
        phase = ResourceCardImportPhase.completed;
      } else {
        phase = ResourceCardImportPhase.reviewing;
      }
    } catch (exception) {
      if (!_isCurrent(generation)) return;
      error = exception;
      phase = ResourceCardImportPhase.failed;
    }
    _notify();
  }

  Future<int?> save(ResourceLibraryMode mode) async {
    final current = draft;
    if (current == null) return null;
    final generation = _generation;
    phase = ResourceCardImportPhase.saving;
    error = null;
    _notify();
    try {
      final saved = await useCase.save(current, mode: mode);
      if (!_isCurrent(generation)) return null;
      phase = ResourceCardImportPhase.completed;
      return saved;
    } catch (exception) {
      if (!_isCurrent(generation)) return null;
      error = exception;
      phase = ResourceCardImportPhase.failed;
      return null;
    }
  }

  void reset() {
    _generation++;
    phase = ResourceCardImportPhase.idle;
    draft = null;
    error = null;
    progressStage = null;
    _notify();
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
