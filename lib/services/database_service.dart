import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/adventure_config.dart';
import '../models/game_state.dart';
import '../models/message.dart';
import '../models/resource_library_mode.dart';
import '../models/world_entry.dart';
import 'auto_backup_service.dart';
import 'repositories/adventure_repository.dart';
import 'repositories/adventure_repository_impl.dart';
import 'repositories/world_entry_repository.dart';
import 'repositories/world_entry_repository_impl.dart';
import 'repositories/library_repository.dart';
import 'repositories/library_repository_impl.dart';
import 'repositories/settings_repository.dart';
import 'repositories/settings_repository_impl.dart';

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
    __adventureRepo = null;
    __worldEntryRepo = null;
    __libraryRepo = null;
    __settingsRepo = null;
  }

  // ─── Repository instances (lazy-initialized, backed by the shared DB) ───

  static IAdventureRepository? __adventureRepo;
  static IAdventureRepository get _adventureRepo =>
      __adventureRepo ??= AdventureRepositoryImpl(getDb: () => database);

  static IWorldEntryRepository? __worldEntryRepo;
  static IWorldEntryRepository get _worldEntryRepo =>
      __worldEntryRepo ??= WorldEntryRepositoryImpl(getDb: () => database);

  static ILibraryRepository? __libraryRepo;
  static ILibraryRepository get _libraryRepo =>
      __libraryRepo ??= LibraryRepositoryImpl(getDb: () => database);

  static ISettingsRepository? __settingsRepo;
  static ISettingsRepository get _settingsRepo =>
      __settingsRepo ??= SettingsRepositoryImpl(getDb: () => database);

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
                    return openDatabase(
                      path,
                      version: 25,
                      onConfigure: (db) async {
                        await db.execute('PRAGMA foreign_keys = ON');
                        await db.rawQuery('PRAGMA journal_mode = WAL');
                      },
                      onCreate: (db, version) async =>
                          await createV25Schema(db),
                      onUpgrade: (db, oldVersion, newVersion) async {
                        if (oldVersion > newVersion) {
                          throw Exception(
                              '数据库版本过高 ($oldVersion > $newVersion)');
                        }
                        await migrateStepByStep(db, oldVersion, newVersion);
                      },
                    );
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

    return openDatabase(
      path,
      version: 25,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
      onCreate: (db, version) async {
        await createV25Schema(db);
        await createCreationLibrarySchema(db);
        _log('全新安装，v25 schema 创建完毕');
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
        try {
          await db.execute('PRAGMA foreign_keys = OFF');
        } catch (_) {}
        await migrateStepByStep(db, oldVersion, newVersion);
        await db.execute('PRAGMA foreign_keys = ON');
        _log('数据库升级完成: v$oldVersion → v$newVersion');
      },
    );
  }

  /// 最新 schema（v17）—— 供全新安装使用
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
      _log('  执行迁移: v9 → v10（messages.image_paths）');
      await safeAddColumn(db, 'messages', 'image_paths', 'TEXT');
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

    _log('migrateStepByStep 全部完成');
  }

  // ─── Adventures ───

  static Future<int> createAdventure(String title, AdventureConfig config) =>
      _adventureRepo.createAdventure(title, config);

  static Future<List<Map<String, dynamic>>> getAdventures() =>
      _adventureRepo.getAdventures();

  static Future<void> deleteAdventure(int id) =>
      _adventureRepo.deleteAdventure(id);

  // ─── Messages ───

  static Future<int> insertMessage(int adventureId, Message msg,
          {int branchId = 0}) =>
      _adventureRepo.insertMessage(adventureId, msg, branchId: branchId);

  static Future<List<Message>> getMessages(int adventureId,
          {int branchId = 0}) =>
      _adventureRepo.getMessages(adventureId, branchId: branchId);

  // ─── Game State ───

  static Future<void> saveGameState(GameState state) =>
      _adventureRepo.saveGameState(state);

  static Future<GameState?> getGameState(int adventureId) =>
      _adventureRepo.getGameState(adventureId);

  // ─── Summaries ───

  static Future<int> saveSummary(int adventureId, String content, int upToId,
          {int branchId = 0, String? stateSnapshot}) =>
      _adventureRepo.saveSummary(adventureId, content, upToId,
          branchId: branchId, stateSnapshot: stateSnapshot);

  static Future<String?> getLatestSummary(int adventureId,
          {int branchId = 0}) =>
      _adventureRepo.getLatestSummary(adventureId, branchId: branchId);

  static Future<int> getLatestSummaryUpToId(int adventureId,
          {int branchId = 0}) =>
      _adventureRepo.getLatestSummaryUpToId(adventureId, branchId: branchId);

  static Future<Map<String, dynamic>?> getLatestSummaryWithSnapshot(
          int adventureId,
          {int branchId = 0}) =>
      _adventureRepo.getLatestSummaryWithSnapshot(adventureId,
          branchId: branchId);

  static Future<List<Map<String, dynamic>>> getSummaries(int adventureId) =>
      _adventureRepo.getSummaries(adventureId);

  static Future<void> cleanupOldSummaries(int adventureId,
          {int branchId = 0, int maxKeep = 5}) =>
      _adventureRepo.cleanupOldSummaries(adventureId,
          branchId: branchId, maxKeep: maxKeep);

  // ─── World Entries ───

  static Future<int> insertWorldEntry(WorldEntry entry) =>
      _worldEntryRepo.insertWorldEntry(entry);

  static Future<List<WorldEntry>> getWorldEntries(int adventureId) =>
      _worldEntryRepo.getWorldEntries(adventureId);

  static Future<void> updateWorldEntry(WorldEntry entry) =>
      _worldEntryRepo.updateWorldEntry(entry);

  static Future<void> deleteWorldEntry(int id) =>
      _worldEntryRepo.deleteWorldEntry(id);

  static Future<void> deleteWorldEntriesByAdventure(int adventureId) =>
      _worldEntryRepo.deleteWorldEntriesByAdventure(adventureId);

  static Future<List<WorldEntry>> getGlobalWorldEntries() =>
      _worldEntryRepo.getGlobalWorldEntries();

  // ─── Branches ───

  static Future<int> createBranch({
    required int adventureId,
    int? parentId,
    required int forkAfterId,
    String name = '',
  }) =>
      _adventureRepo.createBranch(
        adventureId: adventureId,
        parentId: parentId,
        forkAfterId: forkAfterId,
        name: name,
      );

  static Future<List<Map<String, dynamic>>> getBranches(int adventureId) =>
      _adventureRepo.getBranches(adventureId);

  static Future<void> deleteBranch(int id) => _adventureRepo.deleteBranch(id);

  static Future<List<Message>> getMessagesByBranch(
          int adventureId, int branchId) =>
      _adventureRepo.getMessagesByBranch(adventureId, branchId);

  // ─── Bookmarks (v9) ───

  static Future<void> addBookmark(int adventureId, int messageDbId) =>
      _settingsRepo.addBookmark(adventureId, messageDbId);

  static Future<void> removeBookmark(int adventureId, int messageDbId) =>
      _settingsRepo.removeBookmark(adventureId, messageDbId);

  static Future<List<int>> getBookmarkedMessageIds(int adventureId) =>
      _settingsRepo.getBookmarkedMessageIds(adventureId);

  static Future<void> deleteBookmarksByAdventure(int adventureId) =>
      _settingsRepo.deleteBookmarksByAdventure(adventureId);

  // ─── Settings (v9) ───

  static Future<String?> getSetting(String key) =>
      _settingsRepo.getSetting(key);

  static Future<void> setSetting(String key, String value) =>
      _settingsRepo.setSetting(key, value);

  static Future<void> setSettingInt(String key, int value) =>
      _settingsRepo.setSettingInt(key, value);

  static Future<int?> getSettingInt(String key) =>
      _settingsRepo.getSettingInt(key);

  static Future<Map<String, String>> getAllSettings() =>
      _settingsRepo.getAllSettings();

  // ─── Worldview Presets (v6) ───

  static Future<List<Map<String, dynamic>>> getWorldviewPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.getWorldviewPresets(mode: mode);

  static Future<List<Map<String, dynamic>>> searchWorldviewPresets(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.searchWorldviewPresets(query, mode: mode);

  static Future<void> saveWorldviewPreset({
    required String id,
    required String name,
    required String description,
    required String entriesJson,
    required String now,
    String source = '',
    String detailJson = '{}',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.saveWorldviewPreset(
        id: id,
        name: name,
        description: description,
        entriesJson: entriesJson,
        now: now,
        source: source,
        detailJson: detailJson,
        mode: mode,
      );

  static Future<void> deleteWorldviewPreset(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.deleteWorldviewPreset(id, mode: mode);

  // ─── Character Cards (v7) ───

  static Future<List<Map<String, dynamic>>> getCharacterCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.getCharacterCards(mode: mode);

  static Future<List<Map<String, dynamic>>> searchCharacterCards(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.searchCharacterCards(query, mode: mode);

  static Future<void> saveCharacterCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    String weight = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.saveCharacterCard(
        id: id,
        name: name,
        jsonData: jsonData,
        source: source,
        now: now,
        matchingWorldviewId: matchingWorldviewId,
        weight: weight,
        mode: mode,
      );

  static Future<void> deleteCharacterCard(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.deleteCharacterCard(id, mode: mode);

  // ─── Prompt Presets (v7) ───

  static Future<List<Map<String, dynamic>>> getPromptPresets({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.getPromptPresets(mode: mode);

  static Future<void> savePromptPreset({
    required String id,
    required String name,
    required String systemPrompt,
    required String authorsNote,
    required int noteDepth,
    required int noteFrequency,
    required String now,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.savePromptPreset(
        id: id,
        name: name,
        systemPrompt: systemPrompt,
        authorsNote: authorsNote,
        noteDepth: noteDepth,
        noteFrequency: noteFrequency,
        now: now,
        mode: mode,
      );

  static Future<void> deletePromptPreset(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.deletePromptPreset(id, mode: mode);

  // ─── Personas (v7) ───

  static Future<List<Map<String, dynamic>>> getPersonas() =>
      _libraryRepo.getPersonas();

  static Future<void> savePersona({
    required String id,
    required String name,
    required String jsonData,
    required String now,
  }) =>
      _libraryRepo.savePersona(
        id: id,
        name: name,
        jsonData: jsonData,
        now: now,
      );

  static Future<void> deletePersona(String id) =>
      _libraryRepo.deletePersona(id);

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

  // ─── Adventure Templates (v8) ───

  static Future<List<Map<String, dynamic>>> getAdventureTemplates({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.getAdventureTemplates(mode: mode);

  static Future<List<Map<String, dynamic>>> searchAdventureTemplates(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.searchAdventureTemplates(query, mode: mode);

  static Future<void> saveAdventureTemplate({
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
  }) =>
      _libraryRepo.saveAdventureTemplate(
        id: id,
        name: name,
        worldviewName: worldviewName,
        worldviewDesc: worldviewDesc,
        charDataJson: charDataJson,
        npcDataJson: npcDataJson,
        createdAt: createdAt,
        status: status,
        updatedAt: updatedAt,
        contentHash: contentHash,
        mode: mode,
      );

  static Future<void> deleteAdventureTemplate(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.deleteAdventureTemplate(id, mode: mode);

  static Future<void> seedDefaultWorldviews() =>
      _libraryRepo.seedDefaultWorldviews();

  static Future<void> seedDefaultCharacterCards() =>
      _libraryRepo.seedDefaultCharacterCards();

  static Future<void> seedDefaultSkills() => _libraryRepo.seedDefaultSkills();

  // ─── NPC Cards (v11) ───

  static Future<List<Map<String, dynamic>>> getNpcCards({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.getNpcCards(mode: mode);

  static Future<List<Map<String, dynamic>>> searchNpcCards(
    String query, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.searchNpcCards(query, mode: mode);

  static Future<void> saveNpcCard({
    required String id,
    required String name,
    required String jsonData,
    required String source,
    required String now,
    String matchingWorldviewId = '',
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.saveNpcCard(
        id: id,
        name: name,
        jsonData: jsonData,
        source: source,
        now: now,
        matchingWorldviewId: matchingWorldviewId,
        mode: mode,
      );

  static Future<void> deleteNpcCard(
    String id, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.deleteNpcCard(id, mode: mode);

  // ─── Template Status (v11) ───

  static Future<void> updateTemplateStatus(
    String id,
    String status, {
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.updateTemplateStatus(id, status, mode: mode);

  // ─── Import Records (v12) ───

  static Future<List<Map<String, dynamic>>> getImportRecords({
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.getImportRecords(mode: mode);

  static Future<void> saveImportRecord({
    required String fileName,
    required String fileType,
    required String importType,
    required String resultSummary,
    required String createdAt,
    ResourceLibraryMode mode = ResourceLibraryMode.adventure,
  }) =>
      _libraryRepo.saveImportRecord(
        fileName: fileName,
        fileType: fileType,
        importType: importType,
        resultSummary: resultSummary,
        createdAt: createdAt,
        mode: mode,
      );
}
