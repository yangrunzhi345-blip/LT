import '../../models/resource_library_mode.dart';

enum LibraryCardType { character, npc }

class LibraryCardBatchItem {
  final String id;
  final String name;
  final String jsonData;
  final String source;
  final String now;
  final String matchingWorldviewId;
  final String contentHash;
  final String authoringMethod;
  final String aiGenerationDepth;

  const LibraryCardBatchItem({
    required this.id,
    required this.name,
    required this.jsonData,
    required this.source,
    required this.now,
    required this.matchingWorldviewId,
    required this.contentHash,
    this.authoringMethod = '',
    this.aiGenerationDepth = '',
  });
}

/// 内容库仓库接口
/// 管理 worldview_presets、character_cards、prompt_presets、
/// personas、adventure_templates、skills 表 + 种子数据
abstract class ILibraryRepository {
  // ─── Worldview Presets ───
  Future<List<Map<String, dynamic>>> getWorldviewPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<List<Map<String, dynamic>>> searchWorldviewPresets(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> saveWorldviewPreset({
    required String id,
    required String name,
    required String description,
    required String entriesJson,
    required String now,
    String source = '',
    String contentHash = '',
    String detailJson = '{}',
    String authoringMethod = '',
    String aiGenerationDepth = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> deleteWorldviewPreset(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> seedDefaultWorldviews();

  // ─── Character Cards ───
  Future<List<Map<String, dynamic>>> getCharacterCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<List<Map<String, dynamic>>> searchCharacterCards(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> saveCharacterCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    String weight = '',
    String contentHash = '',
    String authoringMethod = '',
    String aiGenerationDepth = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> deleteCharacterCard(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> seedDefaultCharacterCards();

  // ─── Prompt Presets ───
  Future<List<Map<String, dynamic>>> getPromptPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> savePromptPreset({
    required String id,
    required String name,
    required String systemPrompt,
    required String authorsNote,
    required int noteDepth,
    required int noteFrequency,
    required String now,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> deletePromptPreset(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });

  // ─── Personas ───
  Future<List<Map<String, dynamic>>> getPersonas();
  Future<void> savePersona({
    required String id,
    required String name,
    required String jsonData,
    required String now,
  });
  Future<void> deletePersona(String id);

  // ─── Adventure Templates ───
  Future<List<Map<String, dynamic>>> getAdventureTemplates({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<List<Map<String, dynamic>>> searchAdventureTemplates(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> saveAdventureTemplate({
    required String id,
    required String name,
    required String worldviewName,
    required String worldviewDesc,
    required String charDataJson,
    required String npcDataJson,
    required String createdAt,
    String status = 'draft',
    String updatedAt = '',
    String contentHash = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> deleteAdventureTemplate(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> updateTemplateStatus(
    String id,
    String status, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });

  // ─── NPC Cards (v11) ───
  Future<List<Map<String, dynamic>>> getNpcCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<List<Map<String, dynamic>>> searchNpcCards(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> saveNpcCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    String contentHash = '',
    String authoringMethod = '',
    String aiGenerationDepth = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> deleteNpcCard(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });

  /// Saves one AI-import batch atomically and skips an existing
  /// `(mode, card type, content hash)` record.
  Future<int> saveCardBatch({
    required LibraryCardType type,
    required List<LibraryCardBatchItem> items,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });

  // ─── Import Records (v12) ───
  Future<List<Map<String, dynamic>>> getImportRecords({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });
  Future<void> saveImportRecord({
    required String fileName,
    required String fileType,
    required String importType,
    required String resultSummary,
    required String createdAt,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  });

  // ─── Skills (v13) ───
  Future<List<Map<String, dynamic>>> getAllSkills();
  Future<Map<String, dynamic>?> getSkillById(String id);
  Future<void> saveSkill(Map<String, dynamic> skill);
  Future<List<Map<String, dynamic>>> getCharacterSkills(String charId);
  Future<int> saveCharacterSkill(Map<String, dynamic> cs);
  Future<void> updateCharacterSkill(int id, Map<String, dynamic> updates);
  Future<void> seedDefaultSkills();
}
