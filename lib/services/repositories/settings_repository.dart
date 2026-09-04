/// 设置与书签仓库接口
/// 管理 settings、bookmarks 与加密 API Key；调用方不接触裸数据库。
abstract class ISettingsRepository {
  // ─── Bookmarks ───
  Future<void> addBookmark(int adventureId, int messageDbId);
  Future<void> removeBookmark(int adventureId, int messageDbId);
  Future<List<int>> getBookmarkedMessageIds(int adventureId);
  Future<void> deleteBookmarksByAdventure(int adventureId);

  // ─── Settings ───
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);
  Future<void> setSettingInt(String key, int value);
  Future<int?> getSettingInt(String key);
  Future<void> deleteSetting(String key);
  Future<Map<String, String>> getAllSettings();
  Future<void> setSettings(Map<String, String> values);

  // ─── Encrypted API keys ───
  Future<Map<String, String>> getEncryptedApiKeys();
  Future<void> setEncryptedApiKey(String provider, String encryptedKey);
  Future<void> deleteEncryptedApiKey(String provider);

  // ─── Atomic LLM configuration ───
  Future<void> saveLlmConfiguration({
    required String provider,
    required String model,
    required String baseUrl,
    String? recentModels,
  });
}
