import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../application/resource_library/import_models.dart';
import '../application/resource_library/import_use_cases.dart';

enum SceneBatchImportPhase { idle, identifying, importing }

class SceneBatchImportController extends ChangeNotifier {
  final SceneBatchImportUseCase useCase;

  SceneBatchImportPhase phase = SceneBatchImportPhase.idle;
  Object? error;
  bool _disposed = false;
  int _generation = 0;

  SceneBatchImportController({required this.useCase});

  /// 关联角色上下文（展示输入；校验与保存仍在 UseCase）。解码下沉，
  /// 页面不再解析持久化 json_data。
  Map<String, dynamic> relationshipContextOf(Map<String, dynamic> item) {
    Map<String, dynamic> content = {};
    try {
      content = Map<String, dynamic>.from(
          jsonDecode(item['json_data']?.toString() ?? '{}') as Map);
    } catch (_) {}
    return {
      'id': item['id']?.toString() ?? '',
      'name': content['name']?.toString() ?? item['name']?.toString() ?? '',
      'profession': content['profession']?.toString() ?? '',
      'personality': content['personality']?.toString() ?? '',
    };
  }

  String? get errorMessage {
    final value = error;
    if (value == null) return null;
    if (value is ImportValidationException) return value.message;
    return 'AI 服务暂时不可用，请检查模型配置后重试';
  }

  Future<bool> plan(SceneBatchImportRequest request) async {
    final generation = ++_generation;
    phase = SceneBatchImportPhase.importing;
    error = null;
    _notify();
    try {
      await useCase.plan(request);
      if (!_isCurrent(generation)) return false;
      // Planning alone is not completion. Production uses Resource Studio;
      // this compatibility surface cannot manufacture a terminal state.
      phase = SceneBatchImportPhase.idle;
      return true;
    } catch (exception) {
      if (!_isCurrent(generation)) return false;
      error = exception;
      phase = SceneBatchImportPhase.idle;
      return false;
    } finally {
      _notify();
    }
  }

  void reset() {
    _generation++;
    phase = SceneBatchImportPhase.idle;
    error = null;
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
