import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../services/repositories/settings_repository.dart';

class BookmarkManager {
  final VoidCallback notifyParent;
  final ISettingsRepository _settingsRepo;

  List<String> _bookmarkedMessageIds = [];

  List<String> get bookmarkedMessageIds => _bookmarkedMessageIds;

  List<Message> bookmarkedMessages(List<Message> messages) =>
      messages.where((m) => _bookmarkedMessageIds.contains(m.id)).toList();

  BookmarkManager({
    required this.notifyParent,
    required ISettingsRepository settingsRepo,
  }) : _settingsRepo = settingsRepo;

  int? Function() _currentAdventureIdFn = () => null;

  void setAdventureIdProvider(int? Function() fn) {
    _currentAdventureIdFn = fn;
  }

  void toggleBookmark(String id) {
    // 内存状态始终可操作（兼容无冒险场景）
    if (_bookmarkedMessageIds.contains(id)) {
      _bookmarkedMessageIds.remove(id);
    } else {
      _bookmarkedMessageIds.add(id);
    }
    notifyParent();

    // DB 持久化仅在冒险加载后进行（需要整数 message ID）
    final advId = _currentAdventureIdFn();
    if (advId == null) return;
    final dbId = int.tryParse(id);
    if (dbId == null) return;
    if (_bookmarkedMessageIds.contains(id)) {
      _settingsRepo.addBookmark(advId, dbId).catchError((e) {
        debugPrint('[BookmarkManager] addBookmark 失败: $e');
      });
    } else {
      _settingsRepo.removeBookmark(advId, dbId).catchError((e) {
        debugPrint('[BookmarkManager] removeBookmark 失败: $e');
      });
    }
  }

  Future<void> loadBookmarks() async {
    final advId = _currentAdventureIdFn();
    if (advId == null) return;
    final ids = await _settingsRepo.getBookmarkedMessageIds(advId);
    _bookmarkedMessageIds = ids.map((id) => id.toString()).toList();
    notifyParent();
  }

  /// 从 SharedPreferences 迁移旧书签到数据库（一次性）
  Future<void> migrateFromSharedPreferencesToDb() async {
    final advId = _currentAdventureIdFn();
    if (advId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final oldIds = prefs.getStringList('bookmarked_ids');
      if (oldIds != null && oldIds.isNotEmpty) {
        for (final id in oldIds) {
          final dbId = int.tryParse(id);
          if (dbId != null) {
            await _settingsRepo.addBookmark(advId, dbId);
          }
        }
        await prefs.remove('bookmarked_ids');
      }
    } catch (_) {}
  }
}
