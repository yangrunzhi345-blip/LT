import '../../services/repositories/library_repository.dart';

/// 冒险创建初始数据的应用层用例。
///
/// 消除页面与 Controller 对 DatabaseService 静态方法的直接依赖，
/// 统一经 [ILibraryRepository] 读取世界观预设与角色卡。
class AdventureSetupUseCase {
  final ILibraryRepository _repository;

  const AdventureSetupUseCase(this._repository);

  /// 加载冒险模式的世界观预设。
  Future<List<Map<String, dynamic>>> loadWorldviewPresets() {
    return _repository.getWorldviewPresets();
  }

  /// 加载冒险模式的角色卡列表。
  Future<List<Map<String, dynamic>>> loadCharacterCards() {
    return _repository.getCharacterCards();
  }

  /// Loads NPC assets available to adventure assembly.
  Future<List<Map<String, dynamic>>> loadNpcCards() {
    return _repository.getNpcCards();
  }
}
