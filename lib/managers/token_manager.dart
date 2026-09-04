import 'package:flutter/foundation.dart';
import '../services/repositories/settings_repository.dart';

class _TokenEntry {
  final DateTime timestamp;
  final int tokens;
  final String model;
  const _TokenEntry(
      {required this.timestamp, required this.tokens, required this.model});
}

class TokenManager {
  final VoidCallback notifyParent;
  VoidCallback? _notifyToken; // P1-01: token-only notification (high frequency)
  final ISettingsRepository _settingsRepo;

  int _sessionTokens = 0;
  int _totalTokens = 0;
  final List<int> _messageTokens = [];
  final List<_TokenEntry> _tokenHistory = [];

  int get sessionTokens => _sessionTokens;
  int get totalTokens => _totalTokens;
  List<int> get messageTokens => _messageTokens;

  TokenManager({
    required this.notifyParent,
    VoidCallback? notifyToken,
    required ISettingsRepository settingsRepo,
  })  : _notifyToken = notifyToken,
        _settingsRepo = settingsRepo;

  /// P1-01: 延迟设置 token 专用通知（由 ChatProvider 在构造链完成后调用）
  void setNotifyToken(VoidCallback cb) => _notifyToken = cb;

  Future<void> loadPersistedTotalTokens() async {
    _totalTokens = await _settingsRepo.getSettingInt('total_tokens') ?? 0;
  }

  void trackTokens(int tokens, String currentModel) {
    _sessionTokens += tokens;
    _totalTokens += tokens;
    _messageTokens.add(tokens);
    _tokenHistory.add(_TokenEntry(
        timestamp: DateTime.now(), tokens: tokens, model: currentModel));
    _settingsRepo
        .setSettingInt('total_tokens', _totalTokens)
        .catchError((e) => debugPrint('[TokenManager] 保存Token统计失败: $e'));
    _notifyToken?.call(); // P1-01: 仅触发 token 相关 Widget 重建
    notifyParent();
  }

  void resetSessionTokens() {
    _sessionTokens = 0;
    _messageTokens.clear();
    notifyParent();
  }

  Map<String, dynamic> getTokenSummary() {
    final modelUsage = <String, int>{};
    for (final e in _tokenHistory) {
      modelUsage[e.model] = (modelUsage[e.model] ?? 0) + e.tokens;
    }
    return {
      'sessionTokens': _sessionTokens,
      'totalTokens': _totalTokens,
      'avgPerMessage': _messageTokens.isEmpty
          ? 0
          : _messageTokens.reduce((a, b) => a + b) ~/ _messageTokens.length,
      'modelUsage': modelUsage,
    };
  }
}
