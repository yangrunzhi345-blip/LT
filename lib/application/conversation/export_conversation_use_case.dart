import 'dart:io' show Directory, File, Platform;

import 'package:path_provider/path_provider.dart';

/// 对话导出到文件的用例。
///
/// 桌面平台写入 Downloads/NarrAItor/，移动平台写入应用文档目录；
/// 标题中的非法文件名字符会被替换。UI 层不再直接触碰文件系统。
class ConversationExportUseCase {
  const ConversationExportUseCase();

  /// 保存导出内容到文件，成功返回绝对路径，失败返回 null。
  Future<String?> saveToFile({
    required String content,
    required String extension,
    required String title,
  }) async {
    try {
      final sanitized = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final filename = '$sanitized.$extension';

      String dirPath;
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        final home = Platform.environment['HOME'] ??
            Platform.environment['USERPROFILE'] ??
            '.';
        dirPath = '$home/Downloads/NarrAItor';
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        dirPath = appDir.path;
      }

      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final file = File('$dirPath/$filename');
      await file.writeAsString(content);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
