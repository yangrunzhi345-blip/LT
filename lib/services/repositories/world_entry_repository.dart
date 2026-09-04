import '../../models/world_entry.dart';

/// 世界知识条目仓库接口
/// 管理 world_entries 表
abstract class IWorldEntryRepository {
  Future<int> insertWorldEntry(WorldEntry entry);
  Future<List<WorldEntry>> getWorldEntries(int adventureId);
  Future<void> updateWorldEntry(WorldEntry entry);
  Future<void> deleteWorldEntry(int id);
  Future<void> deleteWorldEntriesByAdventure(int adventureId);
  Future<List<WorldEntry>> getGlobalWorldEntries();
}
