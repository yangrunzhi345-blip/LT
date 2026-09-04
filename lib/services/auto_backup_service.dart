import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// 纯本地数据库自动备份服务
///
/// 策略：
/// - 应用正常退出时备份
/// - 每 10 次消息发送检查一次（防 crash 丢数据）
/// - 保留最近 3 份备份
class AutoBackupService {
  static const _maxBackups = 3;
  static int _messageCount = 0;
  static const _backupInterval = 10;

  /// 调用方每次成功发送/接收消息后调用
  static Future<void> onMessageSent({String? databasePath}) async {
    _messageCount++;
    if (_messageCount % _backupInterval == 0) {
      await backup(databasePath: databasePath);
    }
  }

  /// 应用退出时调用
  static Future<void> onAppExit({String? databasePath}) async {
    await backup(databasePath: databasePath);
  }

  /// 执行数据库备份（非关键路径，失败静默）
  static Future<void> backup({String? databasePath}) async {
    try {
      final dbPath =
          databasePath ?? join(await getDatabasesPath(), 'adventures.db');
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return;

      final backupDir = Directory(join(dirname(dbPath), 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupPath = join(backupDir.path, 'adventures_$timestamp.db');
      Database? snapshotConnection;
      try {
        snapshotConnection = await openDatabase(
          dbPath,
          singleInstance: false,
          readOnly: false,
        );
        final escapedBackupPath = backupPath.replaceAll("'", "''");
        await snapshotConnection.execute("VACUUM INTO '$escapedBackupPath'");
      } catch (_) {
        final partialBackup = File(backupPath);
        if (await partialBackup.exists()) await partialBackup.delete();
        rethrow;
      } finally {
        await snapshotConnection?.close();
      }

      // 清理旧备份
      await _rotateBackups(backupDir);

      debugPrint('[AutoBackup] 备份完成: $backupPath');
    } catch (e) {
      debugPrint('[AutoBackup] 备份失败: $e');
    }
  }

  /// 删除旧备份，仅保留最近 _maxBackups 份
  static Future<void> _rotateBackups(Directory backupDir) async {
    try {
      final files =
          await backupDir.list().where((e) => e.path.endsWith('.db')).toList();

      // 按文件名（含时间戳）降序排列
      files.sort((a, b) => b.path.compareTo(a.path));

      // 删除超出数量的旧备份
      for (final file in files.skip(_maxBackups)) {
        await File(file.path).delete();
        debugPrint('[AutoBackup] 清理旧备份: ${file.path}');
      }
    } catch (e) {
      debugPrint('[AutoBackup] 清理旧备份失败: $e');
    }
  }

  /// 从备份恢复（返回 true 表示恢复成功）
  static Future<bool> restoreFromBackup({String? databasePath}) async {
    try {
      final dbPath =
          databasePath ?? join(await getDatabasesPath(), 'adventures.db');
      final backupDir = Directory(join(dirname(dbPath), 'backups'));
      if (!await backupDir.exists()) return false;

      final files =
          await backupDir.list().where((e) => e.path.endsWith('.db')).toList();

      if (files.isEmpty) return false;

      // 按时间排序，取最新的
      files.sort((a, b) => b.path.compareTo(a.path));
      final latestBackup = files.first;

      // 先验证备份文件
      final backupFile = File(latestBackup.path);
      if (!await backupFile.exists()) return false;

      try {
        final checkDb = await openDatabase(
          latestBackup.path,
          readOnly: true,
          singleInstance: false,
        );
        final result = await checkDb.rawQuery('PRAGMA integrity_check');
        await checkDb.close();
        final status = result.first.values.first.toString();
        if (status != 'ok') return false;
      } catch (_) {
        return false;
      }

      // 覆盖当前数据库
      await backupFile.copy(dbPath);
      debugPrint('[AutoBackup] 从备份恢复成功: $latestBackup');
      return true;
    } catch (e) {
      debugPrint('[AutoBackup] 恢复失败: $e');
      return false;
    }
  }
}
