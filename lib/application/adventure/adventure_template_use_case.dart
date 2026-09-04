import '../../services/repositories/library_repository.dart';
import '../../utils/content_hasher.dart';

/// 冒险模板的应用层用例 — 唯一模板实现。
///
/// 收敛 home_controller、landing_screen、adventure_builder 三处重复的
/// 模板读取 / ContentHasher 去重 / 保存逻辑，统一经 [ILibraryRepository]。
class AdventureTemplateUseCase {
  final ILibraryRepository _repository;

  const AdventureTemplateUseCase(this._repository);

  /// 加载全部冒险模板。
  Future<List<Map<String, dynamic>>> loadTemplates() {
    return _repository.getAdventureTemplates();
  }

  /// 保存模板（含 ContentHasher 去重）。
  ///
  /// 返回 false 表示内容已存在（去重命中）。
  Future<bool> saveAsTemplate({
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
  }) async {
    final content =
        '$name|$worldviewName|$worldviewDesc|$charDataJson|$npcDataJson';
    final hash =
        contentHash.isNotEmpty ? contentHash : ContentHasher.hash(content);
    final templates = await _repository.getAdventureTemplates();
    final exists = templates.any(
      (template) => template['content_hash']?.toString() == hash,
    );
    if (exists) return false;

    await _repository.saveAdventureTemplate(
      id: id,
      name: name,
      worldviewName: worldviewName,
      worldviewDesc: worldviewDesc,
      charDataJson: charDataJson,
      npcDataJson: npcDataJson,
      createdAt: createdAt,
      status: status,
      updatedAt: updatedAt,
      contentHash: hash,
    );
    return true;
  }

  /// 删除模板。
  Future<void> deleteTemplate(String id) {
    return _repository.deleteAdventureTemplate(id);
  }
}
