import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/resource_library_mode.dart';
import '../application/resources/legacy_library_row_purger.dart';
import '../application/resources/resource_owned_state_purger.dart';
import '../application/resources/resource_library_trash_bridge.dart';
import '../application/resources/resource_revision_repository.dart';
import '../application/resources/resource_revision_service.dart';
import '../application/resources/resource_trash_repository.dart';
import '../application/resources/resource_trash_service.dart';
import '../services/repositories/resource_tree_repository_impl.dart';
import 'auto_backup_service.dart';
import 'repositories/world_embedding_repository.dart';
import 'repositories/world_embedding_repository_impl.dart';
import 'repositories/library_repository.dart';
import 'repositories/library_repository_impl.dart';

class DatabaseRecoveryRequiredException implements Exception {
  final String databasePath;
  final String? preservedCopyPath;
  final Object? cause;

  const DatabaseRecoveryRequiredException(
    this.databasePath, {
    this.preservedCopyPath,
    this.cause,
  });

  @override
  String toString() => '数据库无法安全打开，原文件已保留，请从备份恢复。'
      ' databasePath=$databasePath'
      '${preservedCopyPath == null ? '' : ' preservedCopy=$preservedCopyPath'}';
}

class DatabaseService {
  /// Current schema version. Both open paths use it, so a version bump only
  /// happens in one place (Phase 2 moved it from v31 to v32; Phase 8 Round 2
  /// moved it from v39 to v40 to add compression worker leases; Phase 9 moved
  /// it from v40 to v41 to add revision / autosave / trash tables; Phase 10
  /// moved it from v41 to v42 to add assembly readiness / index tables and the
  /// world entry revision provenance column; v43 completes cleanup of legacy
  /// Quest / World Map tables in databases already at v42; v44 persists the AI
  /// resource target length used by blueprint planning).
  static const int schemaVersion = 44;

  static Database? _db;
  static Future<Database>? _opening;

  /// 自定义数据库目录（测试用）。设置后 _initDb() 将使用此目录而非默认路径。
  static String? customDbDir;

  /// 测试用：重置数据库实例（强制下次访问时创建新连接）
  static Future<void> resetDatabase() async {
    try {
      await _opening?.timeout(const Duration(milliseconds: 500));
    } catch (_) {}
    try {
      await _db?.close();
    } catch (_) {}
    _db = null;
    _opening = null;
    // Also reset repository caches
    __worldEmbeddingRepo = null;
    __libraryRepo = null;
    __libraryTrash = null;
  }

  // ─── Repository instances (lazy-initialized, backed by the shared DB) ───

  static IWorldEmbeddingRepository? __worldEmbeddingRepo;
  static IWorldEmbeddingRepository get _worldEmbeddingRepo =>
      __worldEmbeddingRepo ??=
          WorldEmbeddingRepositoryImpl(getDb: () => database);
  static IWorldEmbeddingRepository get worldEmbeddingRepo =>
      _worldEmbeddingRepo;

  static ILibraryRepository? __libraryRepo;
  static ILibraryRepository get _libraryRepo => __libraryRepo ??=
      LibraryRepositoryImpl(getDb: () => database, trashBridge: _libraryTrash);

  /// Phase 9 recycle-bin bridge used by the Resource Library.
  ///
  /// Built here (rather than in a Riverpod provider) because the library
  /// repository is a lazily-created singleton owned by this service. It shares
  /// this service's database accessor, so it sees exactly the same data as the
  /// provider-side stack.
  static ResourceLibraryTrashBridge? __libraryTrash;
  static ResourceLibraryTrashBridge get _libraryTrash =>
      __libraryTrash ??= _buildLibraryTrash();

  /// The single source of the Phase 9 recycle-bin bridge.
  ///
  /// Every production `LibraryRepositoryImpl` construction site — the Riverpod
  /// `libraryRepoProvider` chain included — must take its bridge from here.
  /// Round 2 acceptance (R2-B1) found that two independent assemblies existed
  /// and only one was wired, which turned the fail-closed delete guard into
  /// "deletes are impossible" on the main UI. One source makes a half-wired
  /// assembly structurally impossible again. The bridge only closes over
  /// [database], so it stays valid across `resetDatabase()`.
  static ResourceLibraryTrashBridge get libraryTrashBridge => _libraryTrash;

  static ResourceLibraryTrashBridge _buildLibraryTrash() {
    Future<Database> getDb() => database;
    final tree = ResourceTreeRepositoryImpl(getDb: getDb);
    final revisions = ResourceRevisionRepositoryImpl(getDb: getDb);
    final engine = RevisionCaptureEngine(
      revisionRepository: revisions,
      treeBoundary: tree,
    );
    final trash = ResourceTrashService(
      repository: ResourceTrashRepositoryImpl(getDb: getDb),
      treeBoundary: tree,
      captureEngine: engine,
      getDb: getDb,
      // The only path allowed to remove a legacy row (explicit permanent delete).
      legacyRowPort: LegacyLibraryRowPurger(getDb: getDb),
      // R03-B: auxiliary state (revisions, autosaves, compression, generation,
      // assembly) is discharged inside the purge transaction itself.
      ownedStatePort: ResourceOwnedStatePurger(),
    );
    return ResourceLibraryTrashBridge(getDb: getDb, trashService: trash);
  }

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final opening = _opening;
    if (opening != null) return opening;
    final future = _initDb();
    _opening = future;
    try {
      final db = await future;
      _db = db;
      return db;
    } finally {
      _opening = null;
    }
  }

  /// 日志输出（调试时可用 debugPrint，发布时由 Flutter 自动截断）
  static void _log(String message) {
    debugPrint('[DB] $message');
  }

  /// 检查指定表是否存在于数据库中
  static Future<bool> tableExists(Database db, String table) async {
    final result = await db.rawQuery(
      "SELECT count(*) AS cnt FROM sqlite_master "
      "WHERE type='table' AND name=?",
      [table],
    );
    return (result.first['cnt'] as int) > 0;
  }

  /// 检查指定表中是否存在指定字段（幂等 ADD COLUMN 的前提）
  static Future<bool> columnExists(
    Database db,
    String table,
    String column,
  ) async {
    final result = await db.rawQuery('PRAGMA table_info($table)');
    return result.any((c) => c['name'] == column);
  }

  /// 安全执行 ALTER TABLE ADD COLUMN（仅当表和字段均合法时才执行）
  ///
  /// ⚠️ 安全约束：调用方必须传入硬编码字面量，禁止拼接用户输入。
  /// 参数名通过正则白名单校验，仅允许字母数字下划线。
  static Future<void> safeAddColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    // 白名单验证：仅允许合法的 SQL 标识符
    final ident = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');
    if (!ident.hasMatch(table) || !ident.hasMatch(column)) {
      _log('safeAddColumn: 非法标识符 table="$table" column="$column"，已拒绝');
      return;
    }
    if (!await tableExists(db, table)) {
      _log('safeAddColumn: 表 "$table" 不存在，跳过添加字段 $column');
      return;
    }
    if (await columnExists(db, table, column)) {
      _log('safeAddColumn: 字段 "$table.$column" 已存在，跳过');
      return;
    }
    _log('safeAddColumn: 添加字段 "$table.$column" ($definition)');
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  static Future<Database> _initDb() async {
    // 支持自定义目录覆盖（测试隔离用）
    final dbPath = customDbDir ?? await getDatabasesPath();
    final path = join(dbPath, 'adventures.db');

    // 数据库文件完整性检查（Web 端跳过，sqflite 不支持 Web）
    if (!kIsWeb && await File(path).exists()) {
      String? preservedCopyPath;
      try {
        final checkDb = await openDatabase(
          path,
          readOnly: true,
          singleInstance: false,
        );
        final result = await checkDb.rawQuery('PRAGMA integrity_check');
        await checkDb.close();
        final status = result.first.values.first.toString();
        if (status != 'ok') {
          _log('数据库完整性检查失败: $status');
          // 保留损坏的数据库副本用于手动恢复
          final corruptPath =
              '$path.corrupt.${DateTime.now().millisecondsSinceEpoch}';
          await File(path).copy(corruptPath);
          preservedCopyPath = corruptPath;
          _log('已保留损坏数据库副本: $corruptPath');

          // 尝试从备份恢复
          try {
            final backupDir = Directory(join(dirname(path), 'backups'));
            if (await backupDir.exists()) {
              final files = await backupDir
                  .list()
                  .where((e) => e.path.endsWith('.db'))
                  .toList();
              files.sort((a, b) => b.path.compareTo(a.path));
              for (final backup in files) {
                try {
                  final backupFile = File(backup.path);
                  final checkBackup = await openDatabase(
                    backup.path,
                    readOnly: true,
                    singleInstance: false,
                  );
                  final backupResult =
                      await checkBackup.rawQuery('PRAGMA integrity_check');
                  await checkBackup.close();
                  if (backupResult.first.values.first.toString() == 'ok') {
                    await backupFile.copy(path);
                    _log('从备份恢复成功: ${backup.path}');
                    // 等待恢复库真正打开，才能让失败回到外层恢复流程处理。
                    final restoredDb = await openDatabase(
                      path,
                      version: DatabaseService.schemaVersion,
                      onConfigure: (db) async {
                        await db.execute('PRAGMA foreign_keys = ON');
                        await db.rawQuery('PRAGMA journal_mode = WAL');
                      },
                      onCreate: (db, version) async =>
                          await createV44Schema(db),
                      onUpgrade: (db, oldVersion, newVersion) async {
                        if (oldVersion > newVersion) {
                          throw Exception(
                              '数据库版本过高 ($oldVersion > $newVersion)');
                        }
                        await migrateStepByStep(db, oldVersion, newVersion);
                      },
                    );
                    await _verifyForeignKeysEnabled(restoredDb);
                    return restoredDb;
                  }
                } catch (_) {
                  continue; // 尝试下一个备份
                }
              }
              _log('所有备份均不可用，已保留原数据库并停止启动');
            }
          } catch (_) {}
          throw DatabaseRecoveryRequiredException(
            path,
            preservedCopyPath: preservedCopyPath,
          );
        }
      } on DatabaseRecoveryRequiredException {
        rethrow;
      } catch (openError) {
        // 文件存在但完全无法打开 — 尝试恢复
        try {
          if (preservedCopyPath == null) {
            final corruptPath =
                '$path.corrupt.${DateTime.now().millisecondsSinceEpoch}';
            await File(path).copy(corruptPath);
            preservedCopyPath = corruptPath;
          }
          final restored =
              await AutoBackupService.restoreFromBackup(databasePath: path);
          if (restored) {
            _log('从备份恢复成功');
          } else {
            _log('无法恢复，已保留损坏的数据库文件');
            throw DatabaseRecoveryRequiredException(
              path,
              preservedCopyPath: preservedCopyPath,
              cause: openError,
            );
          }
        } on DatabaseRecoveryRequiredException {
          rethrow;
        } catch (e) {
          _log('恢复尝试失败，已保留原数据库');
          throw DatabaseRecoveryRequiredException(
            path,
            preservedCopyPath: preservedCopyPath,
            cause: e,
          );
        }
      }
    }

    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: (db, version) async {
        await createV44Schema(db);
        await createCreationLibrarySchema(db);
        _log('全新安装，v44 schema 创建完毕');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        _log('数据库升级: v$oldVersion → v$newVersion');
        if (oldVersion > newVersion) {
          _log('错误: 数据库版本降级 $oldVersion → $newVersion，拒绝执行');
          throw Exception(
            '数据库版本过高 ($oldVersion > $newVersion)，'
            '请安装更新版本的应用。当前数据已保留，不会丢失。',
          );
        }
        try {
          await File(path).copy('$path.backup.v$oldVersion');
          _log('已备份数据库: $path.backup.v$oldVersion');
        } catch (e) {
          _log('备份数据库失败（非致命）: $e');
        }
        await migrateStepByStep(db, oldVersion, newVersion);
        _log('数据库升级完成: v$oldVersion → v$newVersion');
      },
    );
    await _verifyForeignKeysEnabled(db);
    return db;
  }

  static Future<void> _verifyForeignKeysEnabled(Database db) async {
    final rows = await db.rawQuery('PRAGMA foreign_keys');
    final enabled = rows.isNotEmpty && (rows.first.values.first as num) == 1;
    if (!enabled) {
      await db.close();
      throw StateError('数据库 foreign_keys 策略未生效，已拒绝继续使用连接');
    }
  }

  /// Latest schema — used for new installations.
  static Future<void> createV22Schema(Database db) async {
    await createV17Schema(db);
    await createSceneDialogueSchema(db);
  }

  static Future<void> createV23Schema(Database db) async {
    await createV22Schema(db);
    await safeAddColumn(
        db, 'worldview_presets', 'detail_json', "TEXT NOT NULL DEFAULT '{}'");
    await safeAddColumn(db, 'worldview_presets', 'detail_search_text',
        "TEXT NOT NULL DEFAULT ''");
    await safeAddColumn(
        db, 'world_entries', 'source_type', "TEXT NOT NULL DEFAULT ''");
    await safeAddColumn(
        db, 'world_entries', 'source_id', "TEXT NOT NULL DEFAULT ''");
    await safeAddColumn(db, 'world_entries', 'source_snapshot_hash',
        "TEXT NOT NULL DEFAULT ''");
    await db.execute('CREATE INDEX IF NOT EXISTS idx_worldview_detail_search '
        'ON worldview_presets(detail_search_text)');
  }

  static Future<void> createV24Schema(Database db) async {
    await createV23Schema(db);
    await createSceneDialogueGovernanceSchema(db);
  }

  static Future<void> createV25Schema(Database db) async {
    await createV24Schema(db);
    await safeAddColumn(
        db, 'map_nodes', 'terrain_type', "TEXT NOT NULL DEFAULT 'plains'");
  }

  static Future<void> createV26Schema(Database db) async {
    await createV25Schema(db);
    await createSceneRuntimeStateSchema(db);
  }

  static Future<void> createV27Schema(Database db) async {
    await createV26Schema(db);
    await addResourceProvenanceColumns(db);
  }

  static Future<void> createV28Schema(Database db) async {
    await createV27Schema(db);
    await createAdventureRuntimeStateSchema(db);
  }

  static Future<void> createV29Schema(Database db) async {
    await createV28Schema(db);
    await createWorldEntryEmbeddingsSchema(db);
    await dropLegacyQuestAndMapTables(db);
  }

  static Future<void> createV30Schema(Database db) async {
    await createV29Schema(db);
    await safeAddColumn(db, 'world_entry_embeddings', 'embedding_blob', 'BLOB');
  }

  static Future<void> createV31Schema(Database db) async {
    await createV30Schema(db);
    await createResourceTreeSchema(db);
  }

  static Future<void> createV32Schema(Database db) async {
    await createV31Schema(db);
    await createResourceMigrationSchema(db);
  }

  static Future<void> createV33Schema(Database db) async {
    await createV32Schema(db);
    await createResourceCreationSessionSchema(db);
  }

  static Future<void> createV34Schema(Database db) async {
    await createV33Schema(db);
    await safeAddColumn(
      db,
      'resource_creation_sessions',
      'request_fingerprint',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  static Future<void> createV35Schema(Database db) async {
    await createV34Schema(db);
    await createResourceBlueprintSchema(db);
    await createResourceGenerationTaskSchema(db);
  }

  static Future<void> createV36Schema(Database db) async {
    await createV35Schema(db);
    await createResourceGenerationAttemptSchema(db);
  }

  static Future<void> createV37Schema(Database db) async {
    await createV36Schema(db);
    await createResourceGenerationSessionSchema(db);
  }

  /// v38 — Section 精细控制：Section 级校验状态。
  ///
  /// `generation_state` 不落库（由 Phase 5 的 Part 生成任务与已提交正文推导，
  /// 避免与任务表分叉）；`validation_state` 无法推导，因此按 Section 持久化，
  /// 供 Phase 7 Section Controls 查询与展示。
  static Future<void> createV38Schema(Database db) async {
    await createV37Schema(db);
    await addSectionControlColumns(db);
  }

  /// v38 — 为 `resource_sections` 增加校验状态列（幂等）。
  ///
  /// 使用 [safeAddColumn]：重复执行、旧库缺少该表或字段已存在时都会安全跳过，
  /// 因此既可作为升级步骤，也可用于全新安装与恢复路径。
  static Future<void> addSectionControlColumns(Database db) async {
    await safeAddColumn(
      db,
      'resource_sections',
      'validation_state',
      "TEXT NOT NULL DEFAULT 'unvalidated'",
    );
    await safeAddColumn(
      db,
      'resource_sections',
      'validation_message',
      "TEXT NOT NULL DEFAULT ''",
    );
    await safeAddColumn(db, 'resource_sections', 'validated_at', 'TEXT');
  }

  /// v39 — 容量追踪与语义压缩（Phase 8）。
  ///
  /// `resources` 增加容量缓存列，使列表页无需逐资源聚合；新增压缩任务表与压缩
  /// 候选表。候选表只保存“压缩结果”，不写回 `resource_parts.content`——正式 Head 的
  /// 切换属于 Phase 9 的 Revision 边界。
  static Future<void> createV39Schema(Database db) async {
    await createV38Schema(db);
    await addResourceCapacityColumns(db);
    await createResourceCompressionSchema(db);
  }

  /// v40 — 压缩 worker 租约（Phase 8 Round 2）。
  ///
  /// 让 `running` 任务能区分“上个进程遗留的孤儿”和“当前仍在执行的活跃任务”，
  /// 避免恢复逻辑抢占活跃 worker。
  static Future<void> createV40Schema(Database db) async {
    await createV39Schema(db);
    await addCompressionLeaseColumns(db);
  }

  /// v41 — Revision、自动保存草稿与回收站（Phase 9）。
  ///
  /// 三张新表共同为“有损操作”提供可恢复边界：
  /// - `resource_revisions` 保存不可变 revision 的元数据与 parent 链，`is_head`
  ///   部分唯一索引在数据库层保证「每个 (resource, kind) 至多一个 head」。
  /// - `resource_revision_nodes` 保存 revision 相对父 revision 的**节点增量**，
  ///   而不是每次编辑都复制整棵树；从根 revision 逐级应用增量即可重建任意历史状态。
  /// - `resource_autosaves` 保存尚未写入正式树的编辑草稿（checkpoint journal）。
  ///   正常的流式生成不会写这张表：只有已确认的 Part 才会经生成提交链路落库。
  /// - `resource_trash` 保存删除元数据（原父节点、原顺序、原因、保留期），
  ///   删除先写这里再走软删除，永久删除是显式的二次操作。
  ///
  /// 迁移只做 `CREATE TABLE / INDEX IF NOT EXISTS`，不重写任何既有行；外键在
  /// 迁移期间被关闭，因此这里不依赖级联，也不引入跨表数据搬迁。
  static Future<void> createV41Schema(Database db) async {
    await createV40Schema(db);
    await createResourceRevisionSchema(db);
    await createResourceAutosaveSchema(db);
    await createResourceTrashSchema(db);
  }

  /// Latest schema — used for new installations.
  ///
  /// Phase 10 adds the assembly readiness table, the revision-scoped semantic
  /// index documents and the world-entry revision provenance column on top of
  /// v41.
  static Future<void> createV42Schema(Database db) async {
    await createV41Schema(db);
    await createAssemblyReadinessSchema(db);
    await dropLegacyQuestAndMapTables(db);
  }

  /// v43 completes legacy Quest / World Map cleanup for existing v42 files.
  /// Fresh installs already perform the same idempotent cleanup via v42.
  static Future<void> createV43Schema(Database db) async {
    await createV42Schema(db);
    await dropLegacyQuestAndMapTables(db);
  }

  /// v44 persists the requested AI resource prose target across planning
  /// retries and application restarts.
  static Future<void> createV44Schema(Database db) async {
    await createV43Schema(db);
    await safeAddColumn(
      db,
      'resource_creation_sessions',
      'target_characters',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// v42 — Assembly readiness（Phase 10）。
  ///
  /// 设计约束（与 Phase 10 方案一致）：
  /// - `resource_assembly_readiness` 每个资源一行：记录目标 latest-head
  ///   revision/content hash、当前 readiness 状态、可消费的 assembly revision、
  ///   attempt token（并发 CAS 所有权）与验证/失败原因。状态机由
  ///   `ResourceStateMachines.readiness` 冻结，存储层不做迁移推断。
  /// - `resource_assembly_entries` 是绑定到某个 assembly revision 的语义索引
  ///   文档（与 world entry 同构的最小字段），保证
  ///   assembly revision A → 索引文档 A，不与 B 混用。旧 ready revision 的
  ///   文档保留，供用户明确选择旧版本时使用。
  /// - `world_entries.source_revision_id` 记录条目来源的 assembly revision，
  ///   embedding 通过 entry 外键间接继承该 provenance。
  ///
  /// 迁移只做 `CREATE TABLE / INDEX IF NOT EXISTS` 与幂等 `ADD COLUMN`，
  /// 不重写任何既有行。
  static Future<void> createAssemblyReadinessSchema(Database db) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS resource_assembly_readiness (
      resource_id TEXT PRIMARY KEY,
      target_revision_id TEXT NOT NULL DEFAULT '',
      target_content_hash TEXT NOT NULL DEFAULT '',
      state TEXT NOT NULL DEFAULT 'preparing',
      assembly_revision_id TEXT NOT NULL DEFAULT '',
      assembly_content_hash TEXT NOT NULL DEFAULT '',
      attempt_token TEXT NOT NULL DEFAULT '',
      validation_message TEXT NOT NULL DEFAULT '',
      failure_reason TEXT NOT NULL DEFAULT '',
      started_at TEXT NOT NULL DEFAULT '',
      completed_at TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL
    )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_resource_assembly_readiness_state '
      'ON resource_assembly_readiness(state, updated_at)',
    );

    await db.execute('''
    CREATE TABLE IF NOT EXISTS resource_assembly_entries (
      entry_id TEXT PRIMARY KEY,
      resource_id TEXT NOT NULL,
      revision_id TEXT NOT NULL,
      revision_content_hash TEXT NOT NULL,
      keys_json TEXT NOT NULL DEFAULT '[]',
      content TEXT NOT NULL,
      insertion_order INTEGER NOT NULL DEFAULT 0,
      sticky INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_resource_assembly_entries_rev '
      'ON resource_assembly_entries(resource_id, revision_id, insertion_order)',
    );

    await safeAddColumn(
      db,
      'world_entries',
      'source_revision_id',
      "TEXT NOT NULL DEFAULT ''",
    );
  }

  /// Removes quest and map persistence left by pre-v29 databases.
  /// This is idempotent so it is safe when a partially upgraded database is reopened.
  static Future<void> dropLegacyQuestAndMapTables(Database db) async {
    const indexes = [
      'idx_map_nodes_adventure_parent',
      'idx_map_connections_adventure',
      'idx_travel_events_adventure_created',
    ];
    for (final index in indexes) {
      await db.execute('DROP INDEX IF EXISTS $index');
    }
    const tables = [
      'movement_operations',
      'map_layouts',
      'map_extraction_candidates',
      'map_state_events',
      'travel_events',
      'adventure_map_state',
      'adventure_map_connection_states',
      'adventure_map_node_states',
      'map_node_aliases',
      'map_connections',
      'map_nodes',
      'quests',
    ];
    for (final table in tables) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
  }

  /// v41 — Revision 头表与节点增量表（Phase 9）。
  ///
  /// 设计约束（与 Phase 9 方案一致）：
  /// - revision 不可变：行只在创建时写入，之后仅 `is_head` 与清理策略会改动。
  /// - 增量而非全量：`resource_revision_nodes` 只记录相对 `parent_revision_id`
  ///   发生变化的节点，`is_removed = 1` 表示该节点在此 revision 已不存在。
  /// - `parent_revision_id` 为空表示该 revision 是一个可以独立重建的根（完整快照）。
  ///   清理策略在删除最老的一批 revision 之前，会把第一个保留的 revision
  ///   “根化”（写全量快照并清空 parent），因此历史链不会因为清理而断裂。
  static Future<void> createResourceRevisionSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_revisions (
        revision_id TEXT PRIMARY KEY,
        resource_id TEXT NOT NULL,
        kind TEXT NOT NULL DEFAULT 'latestHead',
        cause TEXT NOT NULL DEFAULT 'manualSave',
        parent_revision_id TEXT,
        content_hash TEXT NOT NULL DEFAULT '',
        node_count INTEGER NOT NULL DEFAULT 0,
        char_count INTEGER NOT NULL DEFAULT 0,
        label TEXT NOT NULL DEFAULT '',
        is_head INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_resource_revisions_resource '
            'ON resource_revisions(resource_id, created_at DESC, revision_id)');
    // 每个 (resource_id, kind) 至多一个 head：由数据库而不是调用方保证。
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_resource_revisions_head '
        'ON resource_revisions(resource_id, kind) WHERE is_head = 1');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_revision_nodes (
        revision_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        node_kind TEXT NOT NULL,
        parent_node_id TEXT NOT NULL DEFAULT '',
        title TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'draft',
        sort_order INTEGER NOT NULL DEFAULT 0,
        content TEXT NOT NULL DEFAULT '',
        content_hash TEXT NOT NULL DEFAULT '',
        metadata_json TEXT NOT NULL DEFAULT '{}',
        is_removed INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (revision_id, node_id),
        FOREIGN KEY (revision_id) REFERENCES resource_revisions(revision_id)
          ON DELETE CASCADE
      )
    ''');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_resource_revision_nodes_node '
            'ON resource_revision_nodes(node_id, revision_id)');
  }

  /// v41 — 编辑草稿 checkpoint 表（Phase 9）。
  ///
  /// 只保存**尚未写入正式树**的草稿：文本编辑在 debounce 后先落一行 journal，
  /// 成功写入 `resource_parts.content` 的同一逻辑步骤完成后再删除该行。因此崩溃
  /// 恢复时“树里有内容 + 草稿行仍在”可以判定为已应用，而“草稿行内容新于树”才是
  /// 真正需要用户确认的未保存编辑。
  ///
  /// 部分唯一索引保证同一节点至多一条未解决草稿，使 debounce 的重复 checkpoint
  /// 收敛为一条，而不是每 tick 一行。
  static Future<void> createResourceAutosaveSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_autosaves (
        checkpoint_id TEXT PRIMARY KEY,
        resource_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        node_kind TEXT NOT NULL DEFAULT 'part',
        content TEXT NOT NULL DEFAULT '',
        content_hash TEXT NOT NULL DEFAULT '',
        base_updated_at TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_resource_autosaves_node '
        'ON resource_autosaves(node_id)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_resource_autosaves_resource '
            'ON resource_autosaves(resource_id, updated_at DESC)');
  }

  /// v41 — 回收站表（Phase 9）。
  ///
  /// 删除只写这里并走 `deleted_at` 软删除，内容仍在树中，因此恢复不需要第二份
  /// 正文副本。`expires_at` 是保留期截止时间；`restored_at` 非空表示该条已恢复。
  /// 部分唯一索引让同一节点至多一条**未恢复**的回收站记录，使重复删除与重复恢复
  /// 都保持幂等。
  static Future<void> createResourceTrashSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_trash (
        trash_id TEXT PRIMARY KEY,
        resource_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        node_kind TEXT NOT NULL,
        parent_node_id TEXT NOT NULL DEFAULT '',
        original_sort_order INTEGER NOT NULL DEFAULT 0,
        original_status TEXT NOT NULL DEFAULT 'draft',
        original_title TEXT NOT NULL DEFAULT '',
        reason TEXT NOT NULL DEFAULT 'userDelete',
        revision_id TEXT NOT NULL DEFAULT '',
        deleted_at TEXT NOT NULL,
        expires_at TEXT NOT NULL,
        restored_at TEXT,
        restore_outcome TEXT NOT NULL DEFAULT '',
        metadata_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_resource_trash_active_node '
        'ON resource_trash(node_id) WHERE restored_at IS NULL');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_resource_trash_resource '
        'ON resource_trash(resource_id, deleted_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_resource_trash_expiry '
        'ON resource_trash(restored_at, expires_at)');
  }

  /// v40 — 为 `resource_compression_jobs` 增加 worker 归属与租约列（幂等）。
  ///
  /// 旧数据语义：既有 `running` 行迁移后 `worker_id = ''`、`lease_expires_at = NULL`。
  /// 这不表示“不可恢复”，而表示“无法证明归属”，因此它们会被 stale recovery
  /// （`status = 'running' AND lease_expires_at IS NULL`）按 attempts 还原为
  /// `queued` / `failed`，不会留下永不恢复的 legacy running。迁移本身不改写业务行，
  /// 避免在升级期间移动用户的任务状态。
  static Future<void> addCompressionLeaseColumns(Database db) async {
    await safeAddColumn(
      db,
      'resource_compression_jobs',
      'worker_id',
      "TEXT NOT NULL DEFAULT ''",
    );
    await safeAddColumn(
      db,
      'resource_compression_jobs',
      'claimed_at',
      'TEXT',
    );
    await safeAddColumn(
      db,
      'resource_compression_jobs',
      'lease_expires_at',
      'TEXT',
    );
  }

  /// v39 — 为 `resources` 增加容量缓存列（幂等）。
  ///
  /// 缓存列只是投影：权威值始终由一次聚合查询即时计算，缓存仅避免列表页做
  /// N 次聚合。因此默认 0 / 'normal' / NULL 对旧数据完全安全。
  ///
  /// 列名刻意不含 `content` 字样：Phase 1 的结构守护要求 `resources` 不出现任何
  /// 正文列，这两个是计数投影而非文本。
  static Future<void> addResourceCapacityColumns(Database db) async {
    await safeAddColumn(
        db, 'resources', 'measured_char_count', 'INTEGER NOT NULL DEFAULT 0');
    await safeAddColumn(db, 'resources', 'measured_token_estimate',
        'INTEGER NOT NULL DEFAULT 0');
    await safeAddColumn(
        db, 'resources', 'section_count', 'INTEGER NOT NULL DEFAULT 0');
    await safeAddColumn(
        db, 'resources', 'part_count', 'INTEGER NOT NULL DEFAULT 0');
    await safeAddColumn(
        db, 'resources', 'archive_char_count', 'INTEGER NOT NULL DEFAULT 0');
    await safeAddColumn(
        db, 'resources', 'capacity_status', "TEXT NOT NULL DEFAULT 'normal'");
    await safeAddColumn(db, 'resources', 'capacity_measured_at', 'TEXT');
  }

  /// v39 — 压缩任务与压缩候选表（Phase 8）。
  ///
  /// `resource_compression_jobs` 由 (resource_id, scope, target_node_id,
  /// source_token) 唯一约束保证“同资源同版本只排队一次”；部分唯一索引进一步
  /// 保证同一目标同时只有一个未结束任务。
  ///
  /// `resource_compression_candidates` 保存压缩正文与保留项清单；`applied_at`
  /// 恒为 NULL，Phase 9 才能发布候选。
  static Future<void> createResourceCompressionSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_compression_jobs (
        job_id TEXT PRIMARY KEY,
        resource_id TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT 'part',
        target_node_id TEXT NOT NULL,
        parent_node_id TEXT NOT NULL DEFAULT '',
        source_token TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'queued',
        attempts INTEGER NOT NULL DEFAULT 0,
        max_attempts INTEGER NOT NULL DEFAULT 2,
        error_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db
        .execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_compression_jobs_dedup '
            'ON resource_compression_jobs(resource_id, scope, target_node_id, '
            'source_token)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_compression_jobs_active_target '
        'ON resource_compression_jobs(resource_id, target_node_id) '
        "WHERE status IN ('queued', 'running')");
    await db.execute('CREATE INDEX IF NOT EXISTS idx_compression_jobs_status '
        'ON resource_compression_jobs(status, created_at)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_compression_candidates (
        candidate_id TEXT PRIMARY KEY,
        job_id TEXT NOT NULL,
        resource_id TEXT NOT NULL,
        scope TEXT NOT NULL DEFAULT 'part',
        target_node_id TEXT NOT NULL,
        original_char_count INTEGER NOT NULL DEFAULT 0,
        compressed_char_count INTEGER NOT NULL DEFAULT 0,
        compressed_content TEXT NOT NULL DEFAULT '',
        retention_json TEXT NOT NULL DEFAULT '{}',
        validation_state TEXT NOT NULL DEFAULT 'validated',
        validation_message TEXT NOT NULL DEFAULT '',
        applied_at TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (job_id) REFERENCES resource_compression_jobs(job_id)
          ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_compression_candidates_job '
        'ON resource_compression_candidates(job_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_compression_candidates_resource '
        'ON resource_compression_candidates(resource_id, created_at DESC)');
  }

  /// v35 — 自适应蓝图（Adaptive Resource Blueprint）表。
  ///
  /// 保存资源大纲规划历史（revision），记录结构、预算与依赖，在确认（confirm）前
  /// 不写入正式 ResourceTree，重规划（replan）保留旧记录但不污染正式树。
  static Future<void> createResourceBlueprintSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_blueprints (
        blueprint_id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        resource_type TEXT NOT NULL,
        suggested_name TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        revision INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'draft',
        target_capacity INTEGER NOT NULL DEFAULT 0,
        blueprint_json TEXT NOT NULL DEFAULT '{}',
        resource_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_blueprints_session '
        'ON resource_blueprints(session_id, revision DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_blueprints_resource '
        'ON resource_blueprints(resource_id)');
  }

  /// v35 — 待生成 Part 任务（Resource Generation Tasks）表。
  ///
  /// Blueprint 确认后在同一事务内创建的待生成任务占位，记录每个 Part 的生成目标、
  /// 预计长度与依赖 Part ID 列表，供 Phase 5 增量生成协议调度。
  static Future<void> createResourceGenerationTaskSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_generation_tasks (
        task_id TEXT PRIMARY KEY,
        blueprint_id TEXT NOT NULL,
        resource_id TEXT NOT NULL,
        section_id TEXT NOT NULL,
        part_id TEXT NOT NULL,
        prompt_goal TEXT NOT NULL DEFAULT '',
        estimated_length INTEGER NOT NULL DEFAULT 0,
        dependencies_json TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'pending',
        sort_order INTEGER NOT NULL DEFAULT 0,
        current_attempt_id TEXT NOT NULL DEFAULT '',
        error_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_tasks_blueprint '
        'ON resource_generation_tasks(blueprint_id, sort_order, task_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_tasks_resource '
        'ON resource_generation_tasks(resource_id, sort_order, task_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_tasks_part '
        'ON resource_generation_tasks(part_id)');
  }

  /// v36 — 正文增量生成尝试记录表（Resource Generation Attempts）。
  ///
  /// 记录每个 Part 每次生成的尝试历史、执行状态、生成字数与错误信息，
  /// 支持幂等重试、超时取消防竞态与崩溃恢复。
  static Future<void> createResourceGenerationAttemptSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_generation_attempts (
        attempt_id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        generation_id TEXT NOT NULL,
        part_id TEXT NOT NULL,
        attempt_number INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'started',
        content_length INTEGER NOT NULL DEFAULT 0,
        error_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (task_id) REFERENCES resource_generation_tasks(task_id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_attempts_task '
        'ON resource_generation_attempts(task_id, attempt_number DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_attempts_gen '
        'ON resource_generation_attempts(generation_id)');
  }

  /// Phase 6.1 — 流式生成运行时会话表（Resource Generation Sessions）。
  ///
  /// 记录资源生成的整体运行时生命周期状态与当前进度，支持断点续跑与崩溃恢复。
  static Future<void> createResourceGenerationSessionSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_generation_sessions (
        session_id TEXT PRIMARY KEY,
        resource_id TEXT NOT NULL,
        blueprint_id TEXT NOT NULL,
        creation_session_id TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'created',
        current_part_id TEXT,
        current_task_id TEXT,
        current_attempt_id TEXT,
        completed_parts_count INTEGER NOT NULL DEFAULT 0,
        total_parts_count INTEGER NOT NULL DEFAULT 0,
        error_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_sessions_resource '
        'ON resource_generation_sessions(resource_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_sessions_blueprint '
        'ON resource_generation_sessions(blueprint_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_gen_sessions_status '
        'ON resource_generation_sessions(status, updated_at DESC)');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_gen_sessions_active_resource
      ON resource_generation_sessions(resource_id)
      WHERE status NOT IN ('completed', 'cancelled')
    ''');
  }

  /// v33 — 统一创建会话表。
  ///
  /// 每个创建入口都通过同一管线写入这里：`idempotency_key` 唯一，重复提交（双击、
  /// 重建后重试）只能命中同一条会话，因此不会产生第二个资源。参考材料的正文保存在
  /// `reference_body`（Phase 4 规划需要），但只记录来源元数据、绝不写日志。
  /// AI 路径只把会话推进到 `planning`，不生成任何正文。
  static Future<void> createResourceCreationSessionSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_creation_sessions (
        session_id TEXT PRIMARY KEY,
        idempotency_key TEXT NOT NULL UNIQUE,
        resource_type TEXT NOT NULL,
        method TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'draft',
        resource_id TEXT,
        reference_kind TEXT NOT NULL DEFAULT 'none',
        reference_label TEXT NOT NULL DEFAULT '',
        reference_file_name TEXT NOT NULL DEFAULT '',
        reference_resource_id TEXT NOT NULL DEFAULT '',
        reference_body TEXT NOT NULL DEFAULT '',
        reference_char_count INTEGER NOT NULL DEFAULT 0,
        target_characters INTEGER NOT NULL DEFAULT 0,
        origin TEXT NOT NULL DEFAULT '',
        request_fingerprint TEXT NOT NULL DEFAULT '',
        error_message TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_creation_sessions_status '
        'ON resource_creation_sessions(status, updated_at DESC)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_creation_sessions_resource '
            'ON resource_creation_sessions(resource_id)');
  }

  /// v32 — 旧资源迁移审计表。
  ///
  /// 每个 legacy 源行对应一条记录，用于可重复、可审计的 Phase 2 迁移：
  /// 只有 `status = 'succeeded'` 且 `source_hash` 与源行当前哈希一致时，兼容读取
  /// 才使用新树，否则回退旧表。`raw_payload` 是损坏 JSON 的隔离字段，原样保存源行
  /// payload，绝不用空对象覆盖；旧表本身始终保留，最终清理由 Phase 12 负责。
  static Future<void> createResourceMigrationSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_migration_records (
        source_table TEXT NOT NULL,
        source_id TEXT NOT NULL,
        migration_version INTEGER NOT NULL,
        source_hash TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        resource_id TEXT,
        error_reason TEXT NOT NULL DEFAULT '',
        raw_payload TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (source_table, source_id, migration_version)
      )
    ''');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_resource_migration_resource '
            'ON resource_migration_records(resource_id)');
  }

  /// v31 — 统一资源内容树（Resource → Section → Part）。
  ///
  /// 三层必须是逻辑树：Section 只通过 `resource_id` 直属 Resource，Part 只通过
  /// `section_id` 直属 Section，不存在第四层或任意递归父子关系。长正文只能落在
  /// `resource_parts.content`；`resources` 上不存在任何 `content` / `content_json`
  /// 巨列，`metadata_json` 只承载运行时核心字段与来源信息。因此读取大型资源不需要
  /// 解析任何一个巨型 JSON。
  ///
  /// `deleted_at` 只提供软删除语义，回收站、删除历史与 30 天清理属于 Phase 9。
  /// 删除不复制旧表数据：世界观 / 角色卡 / NPC 的迁移属于 Phase 2。
  static Future<void> createResourceTreeSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resources (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'draft',
        metadata_json TEXT NOT NULL DEFAULT '{}',
        schema_version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_sections (
        id TEXT PRIMARY KEY,
        resource_id TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'draft',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (resource_id) REFERENCES resources(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS resource_parts (
        id TEXT PRIMARY KEY,
        section_id TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'draft',
        content_hash TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        FOREIGN KEY (section_id) REFERENCES resource_sections(id) ON DELETE CASCADE
      )
    ''');
    // 排序读取固定使用 (sort_order, id)，索引与之一致，避免读取依赖返回顺序。
    await db.execute('CREATE INDEX IF NOT EXISTS idx_resources_type_updated '
        'ON resources(type, updated_at DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_resource_sections_parent '
        'ON resource_sections(resource_id, sort_order, id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_resource_parts_parent '
        'ON resource_parts(section_id, sort_order, id)');
  }

  /// Creates table for world entry embeddings (Hybrid Semantic Retrieval).
  static Future<void> createWorldEntryEmbeddingsSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS world_entry_embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entry_id INTEGER NOT NULL,
        adventure_id INTEGER NOT NULL DEFAULT 0,
        content_hash TEXT NOT NULL,
        model_id TEXT NOT NULL,
        dimensions INTEGER NOT NULL,
        embedding_blob BLOB,
        embedding_json TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (entry_id) REFERENCES world_entries(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_world_embeddings_entry ON world_entry_embeddings(entry_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_world_embeddings_adv ON world_entry_embeddings(adventure_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_world_embeddings_hash ON world_entry_embeddings(content_hash, model_id)');
  }

  /// Creates the immutable state archive and branch-local runtime HEAD.
  static Future<void> createAdventureRuntimeStateSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS adventure_runtime_heads (
        adventure_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 0,
        revision INTEGER NOT NULL DEFAULT 0,
        head_commit_id TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (adventure_id, branch_id),
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS adventure_runtime_entities (
        adventure_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 0,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        state_json TEXT NOT NULL DEFAULT '{}',
        lifecycle_status TEXT NOT NULL DEFAULT 'active',
        last_commit_id TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (adventure_id, branch_id, entity_type, entity_id),
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS adventure_state_commits (
        id TEXT PRIMARY KEY,
        adventure_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 0,
        request_id TEXT NOT NULL,
        parent_commit_id TEXT,
        revision INTEGER NOT NULL,
        context_snapshot_id TEXT,
        summary TEXT NOT NULL DEFAULT '',
        cause_type TEXT NOT NULL DEFAULT 'scene_dialogue',
        cause_ref TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(adventure_id, branch_id, request_id),
        UNIQUE(adventure_id, branch_id, revision),
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS adventure_state_changes (
        id TEXT PRIMARY KEY,
        commit_id TEXT NOT NULL,
        change_index INTEGER NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        change_kind TEXT NOT NULL,
        operation TEXT NOT NULL,
        path TEXT NOT NULL,
        before_json TEXT,
        after_json TEXT,
        reason TEXT NOT NULL,
        provenance_json TEXT NOT NULL DEFAULT '{}',
        visibility TEXT NOT NULL DEFAULT 'internal',
        permanence TEXT NOT NULL DEFAULT 'persistent',
        UNIQUE(commit_id, change_index),
        FOREIGN KEY (commit_id) REFERENCES adventure_state_commits(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_runtime_commits_branch_revision '
        'ON adventure_state_commits(adventure_id, branch_id, revision DESC)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_runtime_changes_commit '
        'ON adventure_state_changes(commit_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_runtime_changes_entity '
        'ON adventure_state_changes(entity_type, entity_id)');
  }

  static Future<void> addResourceProvenanceColumns(Database db) async {
    for (final table in const [
      'worldview_presets',
      'character_cards',
      'npc_cards',
    ]) {
      await safeAddColumn(
        db,
        table,
        'authoring_method',
        "TEXT NOT NULL DEFAULT ''",
      );
      await safeAddColumn(
        db,
        table,
        'ai_generation_depth',
        "TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  static Future<void> createSceneRuntimeStateSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scene_runtime_state (
        adventure_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 0,
        state_json TEXT NOT NULL DEFAULT '{}',
        schema_version INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (adventure_id, branch_id),
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
  }

  static Future<void> createSceneDialogueGovernanceSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scene_presence (
        adventure_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 0,
        actor_id TEXT NOT NULL,
        participant_ids_json TEXT NOT NULL DEFAULT '[]',
        updated_at TEXT NOT NULL,
        PRIMARY KEY (adventure_id, branch_id),
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scene_setting_candidates (
        id TEXT PRIMARY KEY,
        adventure_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 0,
        request_id TEXT NOT NULL,
        type TEXT NOT NULL,
        content TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        UNIQUE(adventure_id, branch_id, content_hash),
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await safeAddColumn(
        db, 'scene_dialogue_turns', 'assistant_client_message_id', 'TEXT');
    await safeAddColumn(
        db, 'scene_dialogue_turns', 'context_snapshot_id', 'TEXT');
    await safeAddColumn(db, 'scene_dialogue_turns', 'diagnostics_json',
        "TEXT NOT NULL DEFAULT '{}' ");
  }

  static Future<void> createSceneDialogueSchema(Database db) async {
    await safeAddColumn(db, 'messages', 'client_message_id', 'TEXT');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS '
        'idx_messages_adv_client_message ON messages(adventure_id, client_message_id) '
        'WHERE client_message_id IS NOT NULL');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scene_dialogue_turns (
        request_id TEXT PRIMARY KEY,
        adventure_id INTEGER NOT NULL,
        branch_id INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_scene_dialogue_turns_adv_branch '
        'ON scene_dialogue_turns(adventure_id, branch_id)');
  }

  static Future<void> createV17Schema(Database db) async {
    await createV7Schema(db);
    // v5/v7 schema 的表缺少 v9+ 新增列，全新安装时使用 safeAddColumn 幂等添加
    await safeAddColumn(
        db, 'summaries', 'branch_id', 'INTEGER NOT NULL DEFAULT 0');
    await safeAddColumn(db, 'messages', 'parent_id', 'INTEGER');
    await safeAddColumn(db, 'messages', 'token_count', 'INTEGER');
    await safeAddColumn(db, 'messages', 'error_type', 'TEXT');
    await safeAddColumn(
        db, 'adventures', 'updated_at', 'TEXT NOT NULL DEFAULT ""');
    await safeAddColumn(db, 'messages', 'edited', 'INTEGER DEFAULT 0');
    // v10: image_paths
    await safeAddColumn(db, 'messages', 'image_paths', 'TEXT');
    // reasoning_content: DeepSeek 思维链内容
    await safeAddColumn(db, 'messages', 'reasoning_content', 'TEXT');
    // v11: worldview_presets / character_cards 增强 + npc_cards + adventure_templates 增强
    await safeAddColumn(db, 'worldview_presets', 'source', "TEXT DEFAULT ''");
    await safeAddColumn(
        db, 'worldview_presets', 'matching_worldview_id', "TEXT DEFAULT ''");
    await safeAddColumn(
        db, 'character_cards', 'matching_worldview_id', "TEXT DEFAULT ''");
    await safeAddColumn(db, 'character_cards', 'weight', "TEXT DEFAULT ''");
    await safeAddColumn(
        db, 'adventure_templates', 'status', "TEXT DEFAULT 'draft'");
    await safeAddColumn(
        db, 'adventure_templates', 'updated_at', "TEXT NOT NULL DEFAULT ''");

    await db.execute('''
      CREATE TABLE IF NOT EXISTS bookmarks (
        adventure_id INTEGER NOT NULL,
        message_id   INTEGER NOT NULL,
        created_at   TEXT NOT NULL,
        PRIMARY KEY (adventure_id, message_id),
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key        TEXT PRIMARY KEY,
        value      TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    // v11: npc_cards
    await db.execute('''
      CREATE TABLE IF NOT EXISTS npc_cards (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        json_data TEXT NOT NULL DEFAULT '{}',
        source TEXT DEFAULT '',
        matching_worldview_id TEXT DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    // v12: import_records
    await db.execute('''
      CREATE TABLE IF NOT EXISTS import_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL DEFAULT '',
        file_type TEXT NOT NULL DEFAULT '',
        import_type TEXT NOT NULL DEFAULT '',
        result_summary TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    // v13: skills + character_skills + game_state 扩展
    await db.execute('''
      CREATE TABLE IF NOT EXISTS skills (
        id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
        description TEXT DEFAULT '', skill_type TEXT DEFAULT 'active',
        category TEXT DEFAULT 'combat', max_level INTEGER DEFAULT 5,
        base_mp_cost INTEGER DEFAULT 0, mp_cost_per_level INTEGER DEFAULT 0,
        effects_json TEXT DEFAULT '{}', effects_per_level_json TEXT DEFAULT '{}',
        prerequisite_skill_id TEXT, prerequisite_level INTEGER DEFAULT 0,
        stat_requirements_json TEXT DEFAULT '{}', icon TEXT DEFAULT '',
        worldview_category TEXT DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS character_skills (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        character_id TEXT NOT NULL, character_type TEXT NOT NULL DEFAULT 'player',
        skill_id TEXT NOT NULL, current_level INTEGER DEFAULT 1,
        experience INTEGER DEFAULT 0,
        FOREIGN KEY (skill_id) REFERENCES skills(id)
      )
    ''');
    await safeAddColumn(db, 'game_state', 'level', 'INTEGER DEFAULT 1');
    await safeAddColumn(db, 'game_state', 'experience', 'INTEGER DEFAULT 0');
    await safeAddColumn(db, 'game_state', 'mp', 'INTEGER DEFAULT 100');
    await safeAddColumn(db, 'game_state', 'max_mp', 'INTEGER DEFAULT 100');
    await safeAddColumn(db, 'game_state', 'base_atk', 'INTEGER DEFAULT 5');
    await safeAddColumn(db, 'game_state', 'base_def', 'INTEGER DEFAULT 3');
    await safeAddColumn(db, 'game_state', 'base_speed', 'INTEGER DEFAULT 5');
    await safeAddColumn(db, 'game_state', 'skill_points', 'INTEGER DEFAULT 0');
    // v14: quests
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quests (
        id TEXT PRIMARY KEY, adventure_id INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '', description TEXT DEFAULT '',
        quest_type TEXT DEFAULT 'side', status TEXT DEFAULT 'active',
        objectives_json TEXT DEFAULT '[]', rewards_json TEXT DEFAULT '[]',
        giver_npc_id TEXT, created_at TEXT NOT NULL,
        completed_at TEXT, expiry TEXT,
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    // v15: equipment + inventory + map
    await db.execute('''
      CREATE TABLE IF NOT EXISTS equipment (
        id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
        icon TEXT DEFAULT '', slot TEXT NOT NULL DEFAULT 'weapon',
        quality TEXT DEFAULT 'common', stats_json TEXT DEFAULT '{}',
        skill_granted TEXT, description TEXT DEFAULT '',
        owner_character_id TEXT, adventure_id INTEGER NOT NULL,
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT, adventure_id INTEGER NOT NULL,
        item_id TEXT NOT NULL, item_type TEXT NOT NULL DEFAULT 'consumable',
        name TEXT NOT NULL DEFAULT '', icon TEXT DEFAULT '',
        quantity INTEGER DEFAULT 1, data_json TEXT DEFAULT '{}',
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS map_nodes (
        id TEXT PRIMARY KEY, adventure_id INTEGER NOT NULL,
        name TEXT NOT NULL DEFAULT '', icon TEXT DEFAULT '',
        node_type TEXT DEFAULT 'wild', description TEXT DEFAULT '',
        explored INTEGER DEFAULT 0, x REAL DEFAULT 0, y REAL DEFAULT 0,
        travel_cost INTEGER DEFAULT 5,
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS map_connections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        node_a_id TEXT NOT NULL, node_b_id TEXT NOT NULL,
        travel_cost INTEGER DEFAULT 5,
        FOREIGN KEY (node_a_id) REFERENCES map_nodes(id) ON DELETE CASCADE,
        FOREIGN KEY (node_b_id) REFERENCES map_nodes(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_adv_branch ON messages(adventure_id, branch_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_branches_adv ON branches(adventure_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_world_entries_adv ON world_entries(adventure_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_summaries_adv_branch ON summaries(adventure_id, branch_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_adventures_created ON adventures(created_at DESC)');
    // v16: 加密 API Key 存储
    await db.execute('''
      CREATE TABLE IF NOT EXISTS api_keys (
        provider      TEXT PRIMARY KEY,
        encrypted_key TEXT NOT NULL DEFAULT '',
        created_at    INTEGER NOT NULL DEFAULT 0,
        updated_at    INTEGER NOT NULL DEFAULT 0
      )
    ''');
    // v17: 内容去重哈希列
    await safeAddColumn(
        db, 'adventure_templates', 'content_hash', "TEXT DEFAULT ''");
    await safeAddColumn(
        db, 'character_cards', 'content_hash', "TEXT DEFAULT ''");
    await safeAddColumn(
        db, 'worldview_presets', 'content_hash', "TEXT DEFAULT ''");
    await safeAddColumn(db, 'npc_cards', 'content_hash', "TEXT DEFAULT ''");
    // v18: 摘要状态快照 + 背包物品角色归属
    await safeAddColumn(db, 'summaries', 'state_snapshot', 'TEXT');
    await safeAddColumn(db, 'inventory_items', 'owner_character_id', 'TEXT');
    // v19: 资料库按冒险/创作模式隔离
    await addResourceLibraryModeColumns(db);
    await createCreationLibrarySchema(db);
    await createNarrativeMapSchema(db);
  }

  static Future<void> createNarrativeMapSchema(Database db) async {
    await safeAddColumn(db, 'map_nodes', 'parent_node_id', 'TEXT');
    await safeAddColumn(
        db, 'map_nodes', 'canonical_name', "TEXT NOT NULL DEFAULT ''");
    await safeAddColumn(
        db, 'map_nodes', 'display_name', "TEXT NOT NULL DEFAULT ''");
    await safeAddColumn(
        db, 'map_nodes', 'map_level', 'INTEGER NOT NULL DEFAULT 1');
    await safeAddColumn(
        db, 'map_nodes', 'position_locked', 'INTEGER NOT NULL DEFAULT 0');
    await safeAddColumn(db, 'map_nodes', 'source_type',
        "TEXT NOT NULL DEFAULT 'narrativeExtraction'");
    await safeAddColumn(
        db, 'map_nodes', 'confidence', "TEXT NOT NULL DEFAULT 'probable'");
    await safeAddColumn(
        db, 'map_nodes', 'created_at', "TEXT NOT NULL DEFAULT ''");
    await safeAddColumn(
        db, 'map_nodes', 'updated_at', "TEXT NOT NULL DEFAULT ''");
    await safeAddColumn(db, 'map_connections', 'adventure_id', 'INTEGER');
    await safeAddColumn(db, 'map_connections', 'connection_type',
        "TEXT NOT NULL DEFAULT 'unknown'");
    await safeAddColumn(db, 'map_connections', 'is_bidirectional',
        'INTEGER NOT NULL DEFAULT 1');
    await safeAddColumn(
        db, 'map_connections', 'travel_time', 'INTEGER NOT NULL DEFAULT 0');
    await safeAddColumn(
        db, 'map_connections', 'energy_cost', 'INTEGER NOT NULL DEFAULT 5');
    await safeAddColumn(
        db, 'map_connections', 'risk_level', 'INTEGER NOT NULL DEFAULT 0');
    await safeAddColumn(db, 'map_connections', 'availability_state',
        "TEXT NOT NULL DEFAULT 'available'");
    await safeAddColumn(db, 'map_connections', 'unlock_conditions_json',
        "TEXT NOT NULL DEFAULT '[]'");
    await safeAddColumn(db, 'map_connections', 'transport_modes_json',
        "TEXT NOT NULL DEFAULT '[]'");
    await safeAddColumn(
        db, 'map_connections', 'source_type', "TEXT NOT NULL DEFAULT 'manual'");
    await safeAddColumn(db, 'map_connections', 'confidence',
        "TEXT NOT NULL DEFAULT 'confirmed'");

    await db.execute('''CREATE TABLE IF NOT EXISTS map_node_aliases (
      id INTEGER PRIMARY KEY AUTOINCREMENT, adventure_id INTEGER NOT NULL,
      node_id TEXT NOT NULL, alias TEXT NOT NULL, normalized_alias TEXT NOT NULL,
      source_type TEXT NOT NULL DEFAULT 'manual', created_at TEXT NOT NULL,
      UNIQUE(adventure_id, normalized_alias),
      FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE,
      FOREIGN KEY (node_id) REFERENCES map_nodes(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS adventure_map_node_states (
      adventure_id INTEGER NOT NULL, node_id TEXT NOT NULL,
      discovery_state TEXT NOT NULL DEFAULT 'unknown',
      availability_state TEXT NOT NULL DEFAULT 'available',
      current_state_json TEXT NOT NULL DEFAULT '{}', exploration_progress INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL, PRIMARY KEY(adventure_id, node_id),
      FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE,
      FOREIGN KEY (node_id) REFERENCES map_nodes(id) ON DELETE CASCADE)''');
    await db
        .execute('''CREATE TABLE IF NOT EXISTS adventure_map_connection_states (
      adventure_id INTEGER NOT NULL, connection_id INTEGER NOT NULL,
      availability_state TEXT NOT NULL DEFAULT 'available', current_state_json TEXT NOT NULL DEFAULT '{}',
      updated_at TEXT NOT NULL, PRIMARY KEY(adventure_id, connection_id),
      FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE,
      FOREIGN KEY (connection_id) REFERENCES map_connections(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS adventure_map_state (
      adventure_id INTEGER PRIMARY KEY, current_node_id TEXT, last_consumed_message_id INTEGER,
      layout_version INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL,
      FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE,
      FOREIGN KEY (current_node_id) REFERENCES map_nodes(id))''');
    await db.execute('''CREATE TABLE IF NOT EXISTS travel_events (
      id TEXT PRIMARY KEY, adventure_id INTEGER NOT NULL, operation_id TEXT NOT NULL UNIQUE,
      from_node_id TEXT NOT NULL, to_node_id TEXT NOT NULL, route_json TEXT NOT NULL DEFAULT '[]',
      started_at_game_time TEXT, arrived_at_game_time TEXT, energy_cost INTEGER NOT NULL DEFAULT 0,
      travel_time INTEGER NOT NULL DEFAULT 0, travel_method TEXT NOT NULL DEFAULT 'walk',
      trigger_message_id TEXT, event_id TEXT, result TEXT NOT NULL DEFAULT 'arrived', created_at TEXT NOT NULL,
      FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS map_state_events (
      id TEXT PRIMARY KEY, adventure_id INTEGER NOT NULL, event_type TEXT NOT NULL,
      target_type TEXT NOT NULL, target_id TEXT NOT NULL, before_state TEXT NOT NULL DEFAULT '{}',
      after_state TEXT NOT NULL DEFAULT '{}', source_message_id TEXT, source_task_id TEXT,
      game_time TEXT, created_at TEXT NOT NULL,
      FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS map_extraction_candidates (
      id TEXT PRIMARY KEY, adventure_id INTEGER NOT NULL, message_id TEXT,
      candidate_name TEXT NOT NULL, normalized_name TEXT NOT NULL, trigger_text TEXT NOT NULL DEFAULT '',
      sentence TEXT NOT NULL DEFAULT '', event_type TEXT NOT NULL DEFAULT 'mention',
      confidence REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'pending',
      proposal_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS map_layouts (
      adventure_id INTEGER NOT NULL, node_id TEXT NOT NULL, map_level INTEGER NOT NULL DEFAULT 1,
      parent_node_id TEXT NOT NULL DEFAULT '', position_x REAL NOT NULL, position_y REAL NOT NULL,
      position_locked INTEGER NOT NULL DEFAULT 0, layout_version INTEGER NOT NULL DEFAULT 1,
      updated_at TEXT NOT NULL, PRIMARY KEY(adventure_id, node_id, map_level, parent_node_id),
      FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE,
      FOREIGN KEY (node_id) REFERENCES map_nodes(id) ON DELETE CASCADE)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS movement_operations (
      operation_id TEXT PRIMARY KEY, adventure_id INTEGER NOT NULL, target_node_id TEXT NOT NULL,
      status TEXT NOT NULL, result_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL, completed_at TEXT,
      FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE)''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_map_nodes_adventure_parent ON map_nodes(adventure_id, parent_node_id, map_level)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_map_connections_adventure ON map_connections(adventure_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_travel_events_adventure_created ON travel_events(adventure_id, created_at)');

    final now = DateTime.now().toIso8601String();
    await db.rawUpdate(
        "UPDATE map_nodes SET canonical_name = name WHERE canonical_name = ''");
    await db.rawUpdate(
        "UPDATE map_nodes SET display_name = name WHERE display_name = ''");
    await db.rawUpdate(
        "UPDATE map_nodes SET created_at = ? WHERE created_at = ''", [now]);
    await db.rawUpdate(
        "UPDATE map_nodes SET updated_at = ? WHERE updated_at = ''", [now]);
    await db.rawUpdate('''UPDATE map_connections SET adventure_id = (
      SELECT adventure_id FROM map_nodes WHERE map_nodes.id = map_connections.node_a_id
    ) WHERE adventure_id IS NULL''');
    await db.rawUpdate(
        'UPDATE map_connections SET energy_cost = travel_cost WHERE energy_cost = 5 AND travel_cost != 5');
    await db.rawUpdate('UPDATE map_nodes SET x = x / 960.0 WHERE x > 1.0');
    await db.rawUpdate('UPDATE map_nodes SET y = y / 720.0 WHERE y > 1.0');
  }

  static const List<String> _resourceLibraryModeTables = [
    'worldview_presets',
    'character_cards',
    'prompt_presets',
    'adventure_templates',
    'npc_cards',
    'import_records',
  ];

  static Future<void> addResourceLibraryModeColumns(Database db) async {
    for (final table in _resourceLibraryModeTables) {
      await safeAddColumn(
        db,
        table,
        'mode',
        "TEXT NOT NULL DEFAULT 'adventure'",
      );
      if (await tableExists(db, table) &&
          await columnExists(db, table, 'mode')) {
        await db.update(
          table,
          {'mode': ResourceLibraryMode.adventure.storageValue},
          where: "mode IS NULL OR mode = ''",
        );
      }
    }
  }

  static Future<void> createCreationLibrarySchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS creation_library_resources (
        id TEXT PRIMARY KEY,
        resource_type TEXT NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        summary TEXT NOT NULL DEFAULT '',
        content_json TEXT NOT NULL DEFAULT '{}',
        source TEXT NOT NULL DEFAULT '',
        source_text TEXT NOT NULL DEFAULT '',
        content_hash TEXT NOT NULL DEFAULT '',
        schema_version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS creation_library_relations (
        resource_id TEXT NOT NULL,
        relation_type TEXT NOT NULL,
        target_resource_id TEXT NOT NULL,
        created_at TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        is_public INTEGER NOT NULL DEFAULT 1,
        is_locked INTEGER NOT NULL DEFAULT 0,
        plot_function TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (resource_id, relation_type, target_resource_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS creation_library_imports (
        id TEXT PRIMARY KEY,
        resource_id TEXT NOT NULL,
        resource_type TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT '',
        input_length INTEGER NOT NULL DEFAULT 0,
        result_summary TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_creation_library_type_updated ON creation_library_resources(resource_type, updated_at DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_creation_library_hash ON creation_library_resources(resource_type, content_hash)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_creation_library_relations_target ON creation_library_relations(target_resource_id)');
  }

  /// v5 schema —— 供旧版迁移使用
  static Future<void> createV5Schema(Database db) async {
    await db.execute('''
      CREATE TABLE adventures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        config TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        adventure_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        reasoning_content TEXT,
        is_html INTEGER DEFAULT 0,
        timestamp TEXT NOT NULL,
        branch_id INTEGER DEFAULT 0,
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE game_state (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        adventure_id INTEGER NOT NULL UNIQUE,
        hp INTEGER DEFAULT 100,
        max_hp INTEGER DEFAULT 100,
        energy INTEGER DEFAULT 100,
        max_energy INTEGER DEFAULT 100,
        gold INTEGER DEFAULT 0,
        inventory TEXT DEFAULT '[]',
        chapter INTEGER DEFAULT 1,
        current_scene TEXT DEFAULT '',
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE summaries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        adventure_id INTEGER NOT NULL,
        content TEXT NOT NULL,
        up_to_id INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE world_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        adventure_id INTEGER NOT NULL DEFAULT 0,
        keys TEXT NOT NULL DEFAULT '[]',
        content TEXT NOT NULL DEFAULT '',
        insertion_order INTEGER DEFAULT 0,
        probability INTEGER DEFAULT 100,
        cooldown INTEGER DEFAULT 0,
        sticky INTEGER DEFAULT 0,
        use_regex INTEGER DEFAULT 0,
        insert_position INTEGER DEFAULT 1,
        recursive INTEGER DEFAULT 0,
        enabled INTEGER DEFAULT 1,
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        adventure_id INTEGER NOT NULL,
        parent_id INTEGER,
        fork_after_id INTEGER NOT NULL,
        name TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_adventure ON messages(adventure_id)');
  }

  static Future<void> createV6Schema(Database db) async {
    await createV5Schema(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS worldview_presets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        entries_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  static Future<void> createV7Schema(Database db) async {
    await createV6Schema(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS character_cards (
        id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
        json_data TEXT NOT NULL DEFAULT '{}', source TEXT DEFAULT '',
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS prompt_presets (
        id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
        system_prompt TEXT NOT NULL DEFAULT '', authors_note TEXT DEFAULT '',
        note_depth INTEGER DEFAULT 0, note_frequency INTEGER DEFAULT 3,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS personas (
        id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
        json_data TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS adventure_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        worldview_name TEXT NOT NULL,
        worldview_desc TEXT NOT NULL,
        char_data_json TEXT NOT NULL,
        npc_data_json TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL
      )
    ''');
  }

  /// 逐版本升级，每个步骤都是幂等操作
  /// 即使部分步骤已执行过（上次迁移中断），重复执行也不会报错
  static Future<void> migrateStepByStep(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    _log('migrateStepByStep: v$oldVersion → v$newVersion');

    // ── v1 → v2：新增 summaries 表 ──
    if (oldVersion < 2) {
      _log('  执行迁移: v1 → v2（summaries 表）');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS summaries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          adventure_id INTEGER NOT NULL,
          content TEXT NOT NULL,
          up_to_id INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
        )
      ''');
      _log('  迁移 v1 → v2 完成');
    }

    // ── v2 → v3：新增 world_entries 表 ──
    // 直接使用含全部新列的 DDL；CREATE TABLE IF NOT EXISTS 确保幂等
    if (oldVersion < 3) {
      _log('  执行迁移: v2 → v3（world_entries 表）');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS world_entries (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          adventure_id INTEGER NOT NULL DEFAULT 0,
          keys TEXT NOT NULL DEFAULT '[]',
          content TEXT NOT NULL DEFAULT '',
          insertion_order INTEGER DEFAULT 0,
          probability INTEGER DEFAULT 100,
          cooldown INTEGER DEFAULT 0,
          sticky INTEGER DEFAULT 0,
          use_regex INTEGER DEFAULT 0,
          insert_position INTEGER DEFAULT 1,
          recursive INTEGER DEFAULT 0,
          enabled INTEGER DEFAULT 1,
          FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
        )
      ''');
      _log('  迁移 v2 → v3 完成');
    }

    // ── v3 → v4：分支支持 ──
    if (oldVersion < 4) {
      _log('  执行迁移: v3 → v4（分支支持）');
      await safeAddColumn(db, 'messages', 'branch_id', 'INTEGER DEFAULT 0');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS branches (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          adventure_id INTEGER NOT NULL,
          parent_id INTEGER,
          fork_after_id INTEGER NOT NULL,
          name TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
        )
      ''');
      _log('  迁移 v3 → v4 完成');
    }

    // ── v4 → v5：世界条目增强（正则 + 注入位置） ──
    // v3 的 CREATE TABLE world_entries 可能已包含这些列，
    // 也可能仅含旧列（因旧版 v3 migration 不含它们）。
    // 使用 safeAddColumn 确保幂等——列已存在则跳过。
    if (oldVersion < 5) {
      _log('  执行迁移: v4 → v5（world_entries 增强）');
      await safeAddColumn(
          db, 'world_entries', 'use_regex', 'INTEGER DEFAULT 0');
      await safeAddColumn(
          db, 'world_entries', 'insert_position', 'INTEGER DEFAULT 1');
      _log('  迁移 v4 → v5 完成');
    }

    // ── v5 → v6：世界观预设表 ──
    if (oldVersion < 6) {
      _log('  执行迁移: v5 → v6（worldview_presets 表）');
      await safeAddColumn(db, 'messages', 'edited', 'INTEGER DEFAULT 0');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS worldview_presets (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL DEFAULT '',
          description TEXT NOT NULL DEFAULT '',
          entries_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      _log('  迁移 v5 → v6 完成');
    }

    // ── v6 → v7：角色卡、提示词预设、人格表 ──
    if (oldVersion < 7) {
      _log('  执行迁移: v6 → v7（角色卡、提示词预设、人格表）');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS character_cards (
          id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
          json_data TEXT NOT NULL DEFAULT '{}', source TEXT DEFAULT '',
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS prompt_presets (
          id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
          system_prompt TEXT NOT NULL DEFAULT '', authors_note TEXT DEFAULT '',
          note_depth INTEGER DEFAULT 0, note_frequency INTEGER DEFAULT 3,
          created_at TEXT NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS personas (
          id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
          json_data TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL
        )
      ''');
      _log('  迁移 v6 → v7 完成');
    }

    // ── v7 → v8：冒险模板表 ──
    if (oldVersion < 8) {
      _log('  执行迁移: v7 → v8（adventure_templates 表）');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS adventure_templates (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          worldview_name TEXT NOT NULL,
          worldview_desc TEXT NOT NULL,
          char_data_json TEXT NOT NULL,
          npc_data_json TEXT NOT NULL DEFAULT '[]',
          created_at TEXT NOT NULL
        )
      ''');
      _log('  迁移 v7 → v8 完成');
    }

    // ── v8 → v9：书签/配置/分支摘要/索引 ──
    if (oldVersion < 9) {
      _log('  执行迁移: v8 → v9（bookmarks/settings/索引）');
      await safeAddColumn(
          db, 'summaries', 'branch_id', 'INTEGER NOT NULL DEFAULT 0');
      await safeAddColumn(db, 'messages', 'parent_id', 'INTEGER');
      await safeAddColumn(db, 'messages', 'token_count', 'INTEGER');
      await safeAddColumn(db, 'messages', 'error_type', 'TEXT');
      await safeAddColumn(
          db, 'adventures', 'updated_at', 'TEXT NOT NULL DEFAULT ""');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS bookmarks (
          adventure_id INTEGER NOT NULL,
          message_id   INTEGER NOT NULL,
          created_at   TEXT NOT NULL,
          PRIMARY KEY (adventure_id, message_id),
          FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key        TEXT PRIMARY KEY,
          value      TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_messages_adv_branch ON messages(adventure_id, branch_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_branches_adv ON branches(adventure_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_world_entries_adv ON world_entries(adventure_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_summaries_adv_branch ON summaries(adventure_id, branch_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_bookmarks_adv ON bookmarks(adventure_id)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_adventures_created ON adventures(created_at DESC)');

      // 标记需要从 SharedPreferences 迁移数据
      await db.insert(
          'settings',
          {
            'key': '_migration_bookmarks_pending',
            'value': 'true',
            'updated_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      _log('  迁移 v8 → v9 完成');
    }

    // ── v9 → v10：消息图片路径 ──
    if (oldVersion < 10) {
      _log('  执行迁移: v9 → v10（messages.image_paths & reasoning_content）');
      await safeAddColumn(db, 'messages', 'image_paths', 'TEXT');
      // 新增 reasoning_content 列，以兼容新版 schema
      await safeAddColumn(db, 'messages', 'reasoning_content', 'TEXT');
      _log('  迁移 v9 → v10 完成');
    }

    // ── v10 → v11：世界观/角色卡增强 + NPC卡表 + 冒险模板字段 ──
    if (oldVersion < 11) {
      _log('  执行迁移: v10 → v11（worldview/character/npc/template增强）');
      await safeAddColumn(
          db, 'worldview_presets', 'source', 'TEXT DEFAULT \'\'');
      await safeAddColumn(db, 'worldview_presets', 'matching_worldview_id',
          'TEXT DEFAULT \'\'');
      await safeAddColumn(
          db, 'character_cards', 'matching_worldview_id', 'TEXT DEFAULT \'\'');
      await safeAddColumn(db, 'character_cards', 'weight', 'TEXT DEFAULT \'\'');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS npc_cards (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL DEFAULT '',
          json_data TEXT NOT NULL DEFAULT '{}',
          source TEXT DEFAULT '',
          matching_worldview_id TEXT DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await safeAddColumn(
          db, 'adventure_templates', 'status', 'TEXT DEFAULT \'draft\'');
      await safeAddColumn(db, 'adventure_templates', 'updated_at',
          'TEXT NOT NULL DEFAULT \'\'');
      _log('  迁移 v10 → v11 完成');
    }

    // ── v11 → v12：导入记录表 ──
    if (oldVersion < 12) {
      _log('  执行迁移: v11 → v12（import_records 表）');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS import_records (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_name TEXT NOT NULL DEFAULT '',
          file_type TEXT NOT NULL DEFAULT '',
          import_type TEXT NOT NULL DEFAULT '',
          result_summary TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL
        )
      ''');
      _log('  迁移 v11 → v12 完成');
    }

    // ── v12 → v13：技能系统 + 角色属性扩展 ──
    if (oldVersion < 13) {
      _log('  执行迁移: v12 → v13（skills/character_skills/game_state扩展）');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS skills (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL DEFAULT '',
          description TEXT DEFAULT '',
          skill_type TEXT DEFAULT 'active',
          category TEXT DEFAULT 'combat',
          max_level INTEGER DEFAULT 5,
          base_mp_cost INTEGER DEFAULT 0,
          mp_cost_per_level INTEGER DEFAULT 0,
          effects_json TEXT DEFAULT '{}',
          effects_per_level_json TEXT DEFAULT '{}',
          prerequisite_skill_id TEXT,
          prerequisite_level INTEGER DEFAULT 0,
          stat_requirements_json TEXT DEFAULT '{}',
          icon TEXT DEFAULT '',
          worldview_category TEXT DEFAULT ''
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS character_skills (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          character_id TEXT NOT NULL,
          character_type TEXT NOT NULL DEFAULT 'player',
          skill_id TEXT NOT NULL,
          current_level INTEGER DEFAULT 1,
          experience INTEGER DEFAULT 0,
          FOREIGN KEY (skill_id) REFERENCES skills(id)
        )
      ''');
      // game_state 扩展
      await safeAddColumn(db, 'game_state', 'level', 'INTEGER DEFAULT 1');
      await safeAddColumn(db, 'game_state', 'experience', 'INTEGER DEFAULT 0');
      await safeAddColumn(db, 'game_state', 'mp', 'INTEGER DEFAULT 100');
      await safeAddColumn(db, 'game_state', 'max_mp', 'INTEGER DEFAULT 100');
      await safeAddColumn(db, 'game_state', 'base_atk', 'INTEGER DEFAULT 5');
      await safeAddColumn(db, 'game_state', 'base_def', 'INTEGER DEFAULT 3');
      await safeAddColumn(db, 'game_state', 'base_speed', 'INTEGER DEFAULT 5');
      await safeAddColumn(
          db, 'game_state', 'skill_points', 'INTEGER DEFAULT 0');
      _log('  迁移 v12 → v13 完成');
    }

    // ── v13 → v14：任务系统 + NPC 好感度 ──
    if (oldVersion < 14) {
      _log('  执行迁移: v13 → v14（quests + supporting_characters.affinity）');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS quests (
          id TEXT PRIMARY KEY,
          adventure_id INTEGER NOT NULL,
          title TEXT NOT NULL DEFAULT '',
          description TEXT DEFAULT '',
          quest_type TEXT DEFAULT 'side',
          status TEXT DEFAULT 'active',
          objectives_json TEXT DEFAULT '[]',
          rewards_json TEXT DEFAULT '[]',
          giver_npc_id TEXT,
          created_at TEXT NOT NULL,
          completed_at TEXT,
          expiry TEXT,
          FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
        )
      ''');
      _log('  迁移 v13 → v14 完成');
    }

    // ── v14 → v15：装备/背包/地图 ──
    if (oldVersion < 15) {
      _log('  执行迁移: v14 → v15（equipment/inventory_items/map）');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS equipment (
          id TEXT PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
          icon TEXT DEFAULT '', slot TEXT NOT NULL DEFAULT 'weapon',
          quality TEXT DEFAULT 'common', stats_json TEXT DEFAULT '{}',
          skill_granted TEXT, description TEXT DEFAULT '',
          owner_character_id TEXT, adventure_id INTEGER NOT NULL,
          FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS inventory_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          adventure_id INTEGER NOT NULL, item_id TEXT NOT NULL,
          item_type TEXT NOT NULL DEFAULT 'consumable',
          name TEXT NOT NULL DEFAULT '', icon TEXT DEFAULT '',
          quantity INTEGER DEFAULT 1, data_json TEXT DEFAULT '{}',
          FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS map_nodes (
          id TEXT PRIMARY KEY, adventure_id INTEGER NOT NULL,
          name TEXT NOT NULL DEFAULT '', icon TEXT DEFAULT '',
          node_type TEXT DEFAULT 'wild', description TEXT DEFAULT '',
          explored INTEGER DEFAULT 0, x REAL DEFAULT 0, y REAL DEFAULT 0,
          travel_cost INTEGER DEFAULT 5,
          FOREIGN KEY (adventure_id) REFERENCES adventures(id) ON DELETE CASCADE
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS map_connections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          node_a_id TEXT NOT NULL, node_b_id TEXT NOT NULL,
          travel_cost INTEGER DEFAULT 5,
          FOREIGN KEY (node_a_id) REFERENCES map_nodes(id) ON DELETE CASCADE,
          FOREIGN KEY (node_b_id) REFERENCES map_nodes(id) ON DELETE CASCADE
        )
      ''');
      _log('  迁移 v14 → v15 完成');
    }

    // ── v15 → v16：API Key 加密存储表 ──
    if (oldVersion < 16) {
      _log('  执行迁移: v15 → v16（api_keys 加密存储表）');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS api_keys (
          provider      TEXT PRIMARY KEY,
          encrypted_key TEXT NOT NULL DEFAULT '',
          created_at    INTEGER NOT NULL DEFAULT 0,
          updated_at    INTEGER NOT NULL DEFAULT 0
        )
      ''');
      _log('  迁移 v15 → v16 完成');
    }

    // ── v16 → v17：内容去重哈希列 ──
    if (oldVersion < 17) {
      _log('  执行迁移: v16 → v17（content_hash 内容去重）');
      await safeAddColumn(
          db, 'adventure_templates', 'content_hash', "TEXT DEFAULT ''");
      await safeAddColumn(
          db, 'character_cards', 'content_hash', "TEXT DEFAULT ''");
      await safeAddColumn(
          db, 'worldview_presets', 'content_hash', "TEXT DEFAULT ''");
      await safeAddColumn(db, 'npc_cards', 'content_hash', "TEXT DEFAULT ''");
      _log('  迁移 v16 → v17 完成');
    }

    // ── v17 → v18：摘要状态快照 + 背包物品角色归属 ──
    if (oldVersion < 18) {
      _log(
          '  执行迁移: v17 → v18（summaries.state_snapshot + inventory_items.owner_character_id）');
      await safeAddColumn(db, 'summaries', 'state_snapshot', 'TEXT');
      await safeAddColumn(db, 'inventory_items', 'owner_character_id', 'TEXT');
      _log('  迁移 v17 → v18 完成');
    }

    // ── v18 → v19：资料库按冒险/创作模式隔离 ──
    if (oldVersion < 19) {
      _log('  执行迁移: v18 → v19（resource library mode）');
      await addResourceLibraryModeColumns(db);
      _log('  迁移 v18 → v19 完成');
    }

    if (oldVersion < 20) {
      _log('  执行迁移: v19 → v20（创作资料库专用表）');
      await createCreationLibrarySchema(db);
      _log('  迁移 v19 → v20 完成');
    }

    if (oldVersion < 21) {
      _log('  执行迁移: v20 → v21（分层叙事空间图谱）');
      await createNarrativeMapSchema(db);
      _log('  迁移 v20 → v21 完成');
    }

    if (oldVersion < 22 && newVersion >= 22) {
      _log('  执行迁移: v21 → v22（场景对话原子提交）');
      await createSceneDialogueSchema(db);
      await db
          .execute("UPDATE messages SET client_message_id = 'legacy-' || id "
              'WHERE client_message_id IS NULL');
      _log('  迁移 v21 → v22 完成');
    }

    if (oldVersion < 23 && newVersion >= 23) {
      _log('  执行迁移: v22 → v23（详细世界观）');
      await safeAddColumn(
          db, 'worldview_presets', 'detail_json', "TEXT NOT NULL DEFAULT '{}'");
      await safeAddColumn(db, 'worldview_presets', 'detail_search_text',
          "TEXT NOT NULL DEFAULT ''");
      await safeAddColumn(
          db, 'world_entries', 'source_type', "TEXT NOT NULL DEFAULT ''");
      await safeAddColumn(
          db, 'world_entries', 'source_id', "TEXT NOT NULL DEFAULT ''");
      await safeAddColumn(db, 'world_entries', 'source_snapshot_hash',
          "TEXT NOT NULL DEFAULT ''");
      await db.execute('CREATE INDEX IF NOT EXISTS idx_worldview_detail_search '
          'ON worldview_presets(detail_search_text)');
      _log('  迁移 v22 → v23 完成');
    }

    if (oldVersion < 24 && newVersion >= 24) {
      _log('  执行迁移: v23 → v24（场景上下文与设定候选）');
      await createSceneDialogueGovernanceSchema(db);
      _log('  迁移 v23 → v24 完成');
    }

    if (oldVersion < 25 && newVersion >= 25) {
      _log('  执行迁移: v24 → v25（地图地形类型）');
      await safeAddColumn(
          db, 'map_nodes', 'terrain_type', "TEXT NOT NULL DEFAULT 'plains'");
      _log('  迁移 v24 → v25 完成');
    }

    if (oldVersion < 26 && newVersion >= 26) {
      _log('  执行迁移: v25 → v26（分支级 Runtime SceneState）');
      await createSceneRuntimeStateSchema(db);
      _log('  迁移 v25 → v26 完成');
    }

    if (oldVersion < 27 && newVersion >= 27) {
      _log('  执行迁移: v26 → v27（资产来源元数据）');
      await addResourceProvenanceColumns(db);
      _log('  迁移 v26 → v27 完成');
    }

    if (oldVersion < 28 && newVersion >= 28) {
      _log('  执行迁移: v27 → v28（Adventure Runtime State Versioning）');
      await createAdventureRuntimeStateSchema(db);
      _log('  迁移 v27 → v28 完成');
    }

    if (oldVersion < 29 && newVersion >= 29) {
      _log('  执行迁移: v28 → v29（World Entry Embeddings 与遗留 Adventure 表清理）');
      await createWorldEntryEmbeddingsSchema(db);
      await dropLegacyQuestAndMapTables(db);
      _log('  迁移 v28 → v29 完成');
    }

    if (oldVersion < 30 && newVersion >= 30) {
      _log('  执行迁移: v29 → v30（World Entry Embeddings 二进制压缩向量存储）');
      await safeAddColumn(
          db, 'world_entry_embeddings', 'embedding_blob', 'BLOB');
      _log('  迁移 v29 → v30 完成');
    }

    if (oldVersion < 31 && newVersion >= 31) {
      _log('  执行迁移: v30 → v31（统一资源内容树 Resource/Section/Part）');
      await createResourceTreeSchema(db);
      _log('  迁移 v30 → v31 完成');
    }

    if (oldVersion < 32 && newVersion >= 32) {
      _log('  执行迁移: v31 → v32（旧资源迁移审计表）');
      await createResourceMigrationSchema(db);
      _log('  迁移 v31 → v32 完成');
    }

    if (oldVersion < 33 && newVersion >= 33) {
      _log('  执行迁移: v32 → v33（统一创建会话表）');
      await createResourceCreationSessionSchema(db);
      _log('  迁移 v32 → v33 完成');
    }
    if (oldVersion < 34 && newVersion >= 34) {
      _log('  执行迁移: v33 → v34（创建请求归属指纹）');
      await safeAddColumn(
        db,
        'resource_creation_sessions',
        'request_fingerprint',
        "TEXT NOT NULL DEFAULT ''",
      );
      _log('  迁移 v33 → v34 完成');
    }
    if (oldVersion < 35 && newVersion >= 35) {
      _log(
          '  执行迁移: v34 → v35（自适应大纲 resource_blueprints 与待生成任务 resource_generation_tasks）');
      await createResourceBlueprintSchema(db);
      await createResourceGenerationTaskSchema(db);
      _log('  迁移 v34 → v35 完成');
    }
    if (oldVersion < 36 && newVersion >= 36) {
      _log('  执行迁移: v35 → v36（正文增量生成尝试记录与状态 tracking）');
      await createResourceGenerationAttemptSchema(db);
      await safeAddColumn(
        db,
        'resource_generation_tasks',
        'current_attempt_id',
        "TEXT NOT NULL DEFAULT ''",
      );
      await safeAddColumn(
        db,
        'resource_generation_tasks',
        'error_message',
        "TEXT NOT NULL DEFAULT ''",
      );
      _log('  迁移 v35 → v36 完成');
    }
    if (oldVersion < 37 && newVersion >= 37) {
      _log('  执行迁移: v36 → v37（流式生成运行时会话）');
      await createResourceGenerationSessionSchema(db);
      _log('  迁移 v36 → v37 完成');
    }
    if (oldVersion < 38 && newVersion >= 38) {
      _log('  执行迁移: v37 → v38（Section 精细控制校验状态）');
      await addSectionControlColumns(db);
      _log('  迁移 v37 → v38 完成');
    }
    if (oldVersion < 39 && newVersion >= 39) {
      _log('  执行迁移: v38 → v39（容量缓存列与语义压缩任务/候选表）');
      await addResourceCapacityColumns(db);
      await createResourceCompressionSchema(db);
      _log('  迁移 v38 → v39 完成');
    }
    if (oldVersion < 40 && newVersion >= 40) {
      _log('  执行迁移: v39 → v40（压缩 worker 归属与租约列）');
      await addCompressionLeaseColumns(db);
      _log('  迁移 v39 → v40 完成');
    }
    if (oldVersion < 41 && newVersion >= 41) {
      _log('  执行迁移: v40 → v41（Revision / 自动保存草稿 / 回收站表）');
      await createResourceRevisionSchema(db);
      await createResourceAutosaveSchema(db);
      await createResourceTrashSchema(db);
      _log('  迁移 v40 → v41 完成');
    }
    if (oldVersion < 42 && newVersion >= 42) {
      _log('  执行迁移: v41 → v42（Assembly readiness / 语义索引文档表）');
      await createAssemblyReadinessSchema(db);
      _log('  迁移 v41 → v42 完成');
    }
    if (oldVersion < 43 && newVersion >= 43) {
      _log('  执行迁移: v42 → v43（完成遗留 Quest / World Map 表清理）');
      await dropLegacyQuestAndMapTables(db);
      _log('  迁移 v42 → v43 完成');
    }
    if (oldVersion < 44 && newVersion >= 44) {
      _log('  执行迁移: v43 → v44（AI 资源目标字数）');
      await safeAddColumn(
        db,
        'resource_creation_sessions',
        'target_characters',
        'INTEGER NOT NULL DEFAULT 0',
      );
      _log('  迁移 v43 → v44 完成');
    }

    _log('migrateStepByStep 全部完成');
  }

  // ─── 内容去重 ───

  /// 检查指定表中是否已存在相同内容哈希的记录
  static Future<bool> contentHashExists(
    String table,
    String hash, {
    ResourceLibraryMode? mode,
  }) async {
    if (hash.isEmpty) return false;
    final db = await database;
    final hasMode =
        await tableExists(db, table) && await columnExists(db, table, 'mode');
    final result = hasMode && mode != null
        ? await db.rawQuery(
            'SELECT COUNT(*) as cnt FROM $table WHERE content_hash = ? AND mode = ?',
            [hash, mode.storageValue],
          )
        : await db.rawQuery(
            'SELECT COUNT(*) as cnt FROM $table WHERE content_hash = ?',
            [hash],
          );
    return (result.first['cnt'] as int) > 0;
  }

  static Future<void> seedDefaultWorldviews() =>
      _libraryRepo.seedDefaultWorldviews();

  static Future<void> seedDefaultCharacterCards() =>
      _libraryRepo.seedDefaultCharacterCards();

  static Future<void> seedDefaultSkills() => _libraryRepo.seedDefaultSkills();
}
