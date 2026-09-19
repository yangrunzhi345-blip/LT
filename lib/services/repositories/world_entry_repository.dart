import '../../models/world_entry.dart';

enum PersistedRowErrorCategory { identity, optionalField, decode }

class PersistedRowDiagnostic {
  final String table;
  final Object? rowId;
  final PersistedRowErrorCategory category;

  const PersistedRowDiagnostic({
    required this.table,
    required this.rowId,
    required this.category,
  });
}

class WorldEntryLoadResult {
  final List<WorldEntry> entries;
  final List<PersistedRowDiagnostic> diagnostics;
  final int sourceRowCount;

  const WorldEntryLoadResult({
    required this.entries,
    required this.diagnostics,
    required this.sourceRowCount,
  });

  bool get isGenuinelyEmpty => sourceRowCount == 0;
  bool get hasCorruptRows => diagnostics.isNotEmpty;

  /// Whether persisted rows existed but none could be safely decoded.
  bool get isAllCorrupt => sourceRowCount > 0 && entries.isEmpty;

  /// Whether valid entries were recovered alongside corrupt rows.
  bool get isPartiallyCorrupt => entries.isNotEmpty && diagnostics.isNotEmpty;
}

class WorldEntryPersistenceCorruptionException implements Exception {
  final String scope;

  const WorldEntryPersistenceCorruptionException(this.scope);

  @override
  String toString() =>
      'WorldEntryPersistenceCorruptionException: all $scope rows are corrupt';
}

/// 世界知识条目仓库接口
/// 管理 world_entries 表
abstract class IWorldEntryRepository {
  Future<int> insertWorldEntry(WorldEntry entry);
  Future<WorldEntryLoadResult> loadWorldEntries(int adventureId);
  Future<WorldEntryLoadResult> loadGlobalWorldEntries();
  Future<List<WorldEntry>> getWorldEntries(int adventureId);
  Future<void> updateWorldEntry(WorldEntry entry);
  Future<void> deleteWorldEntry(int id);
  Future<void> deleteWorldEntriesByAdventure(int adventureId);
  Future<List<WorldEntry>> getGlobalWorldEntries();
}
