import 'package:sqflite/sqflite.dart';
import 'settings_repository.dart';

class SettingsRepositoryImpl implements ISettingsRepository {
  final Future<Database> Function() _getDb;

  SettingsRepositoryImpl({required Future<Database> Function() getDb})
      : _getDb = getDb;

  // ─── Bookmarks ───

  @override
  Future<void> addBookmark(int adventureId, int messageDbId) async {
    final db = await _getDb();
    await db.insert(
        'bookmarks',
        {
          'adventure_id': adventureId,
          'message_id': messageDbId,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<void> removeBookmark(int adventureId, int messageDbId) async {
    final db = await _getDb();
    await db.delete('bookmarks',
        where: 'adventure_id = ? AND message_id = ?',
        whereArgs: [adventureId, messageDbId]);
  }

  @override
  Future<List<int>> getBookmarkedMessageIds(int adventureId) async {
    final db = await _getDb();
    final rows = await db.query('bookmarks',
        columns: ['message_id'],
        where: 'adventure_id = ?',
        whereArgs: [adventureId]);
    return rows.map((r) => r['message_id'] as int).toList();
  }

  @override
  Future<void> deleteBookmarksByAdventure(int adventureId) async {
    final db = await _getDb();
    await db.delete('bookmarks',
        where: 'adventure_id = ?', whereArgs: [adventureId]);
  }

  // ─── Settings ───

  @override
  Future<String?> getSetting(String key) async {
    final db = await _getDb();
    final rows = await db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  /// SQLite 写入（含 DB 锁重试，应对并发测试 / 高负载场景）
  Future<void> _retryWrite(Future<void> Function(Database db) operation) async {
    final db = await _getDb();
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await operation(db);
        return;
      } catch (e) {
        final msg = e.toString();
        // SQLITE_BUSY(5): database is locked — 重试
        if ((msg.contains('database is locked') || msg.contains('code 5')) &&
            attempt < 2) {
          await Future.delayed(Duration(milliseconds: 50 * (attempt + 1)));
          continue;
        }
        rethrow;
      }
    }
  }

  @override
  Future<void> setSetting(String key, String value) async {
    await _retryWrite((db) => db.insert(
        'settings',
        {
          'key': key,
          'value': value,
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace));
  }

  @override
  Future<void> setSettingInt(String key, int value) async {
    await setSetting(key, value.toString());
  }

  @override
  Future<int?> getSettingInt(String key) async {
    final val = await getSetting(key);
    return val != null ? int.tryParse(val) : null;
  }

  @override
  Future<void> deleteSetting(String key) async {
    final db = await _getDb();
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<Map<String, String>> getAllSettings() async {
    final db = await _getDb();
    final rows = await db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  @override
  Future<void> setSettings(Map<String, String> values) async {
    if (values.isEmpty) return;
    await _retryWrite((db) => db.transaction((txn) async {
          final now = DateTime.now().toIso8601String();
          for (final entry in values.entries) {
            await txn.insert(
              'settings',
              {'key': entry.key, 'value': entry.value, 'updated_at': now},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }));
  }

  @override
  Future<Map<String, String>> getEncryptedApiKeys() async {
    final db = await _getDb();
    final rows = await db.query('api_keys');
    return {
      for (final row in rows)
        row['provider'].toString(): row['encrypted_key']?.toString() ?? '',
    };
  }

  @override
  Future<void> setEncryptedApiKey(String provider, String encryptedKey) async {
    await _retryWrite((db) => db.insert(
          'api_keys',
          {
            'provider': provider,
            'encrypted_key': encryptedKey,
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        ));
  }

  @override
  Future<void> deleteEncryptedApiKey(String provider) async {
    await _retryWrite((db) async {
      await db.delete('api_keys', where: 'provider = ?', whereArgs: [provider]);
    });
  }

  @override
  Future<void> saveLlmConfiguration({
    required String provider,
    required String model,
    required String baseUrl,
    String? recentModels,
  }) =>
      setSettings({
        'llm_provider': provider,
        'llm_model': model,
        'llm_model_$provider': model,
        'api_base_url': baseUrl,
        'api_base_url_$provider': baseUrl,
        if (recentModels != null) 'recent_models': recentModels,
      });
}
