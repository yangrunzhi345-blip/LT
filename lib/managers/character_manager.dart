import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/character_card.dart';
import '../models/adventure_config.dart';
import '../utils/content_hasher.dart';
import '../services/database_service.dart';
import '../services/repositories/library_repository.dart';
import '../services/resource_integrity_validator.dart';

class CharacterManager {
  final VoidCallback notifyParent;
  final ILibraryRepository _libraryRepo;

  List<CharacterCard> _savedCharacterCards = [];

  List<CharacterCard> get savedCharacterCards => _savedCharacterCards;

  CharacterManager({
    required this.notifyParent,
    required ILibraryRepository libraryRepo,
  }) : _libraryRepo = libraryRepo;

  Future<String> importCharacterCardJson(String jsonStr) async {
    final card = CharacterCard.parseFromJson(jsonStr, importSource: 'JSON导入');
    if (card == null) return '导入失败：无法解析角色卡 JSON';
    final jsonData = jsonEncode(card.toJson());
    try {
      ResourceIntegrityValidator.validateCharacterCard(
          name: card.name, jsonData: jsonData);
    } on ResourceValidationException catch (error) {
      return '导入失败：$error';
    }
    final contentHash = ContentHasher.hashString(jsonData);
    final now = DateTime.now().toIso8601String();
    try {
      await _libraryRepo.saveCharacterCard(
        id: _cardId(card),
        name: card.name,
        jsonData: jsonData,
        source: card.importSource,
        now: now,
        contentHash: contentHash,
      );
    } catch (e) {
      debugPrint('[CharacterManager] importCharacterCardJson 保存失败: $e');
      return '导入失败：角色卡未保存';
    }
    _applyCharacterCard(card);
    _savedCharacterCards
        .removeWhere((c) => c.name == card.name && c.creator == card.creator);
    _savedCharacterCards.insert(0, card);
    notifyParent();
    return '成功导入角色卡「${card.name}」';
  }

  void _applyCharacterCard(CharacterCard card) {
    if (card.systemPrompt.isNotEmpty) {
      SharedPreferences.getInstance().then((prefs) =>
          prefs.setString('custom_system_prompt', card.systemPrompt));
    }
    // notifyParent() 由调用方负责，避免重复通知
  }

  AdventureConfig buildConfigFromCard(CharacterCard card) {
    return AdventureConfig(
      name: card.name,
      worldview: '',
      personality: card.personality,
      openingScene: card.firstMessage,
      characterCard: card,
    );
  }

  void applyCharacterCard(CharacterCard card) {
    _applyCharacterCard(card);
    notifyParent();
  }

  String _cardId(CharacterCard card) {
    if (card.name.isNotEmpty || card.creator.isNotEmpty) {
      return '${card.name}_${card.creator}';
    }
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<void> saveCharacterCard(CharacterCard card) async {
    final jsonData = jsonEncode(card.toJson());
    ResourceIntegrityValidator.validateCharacterCard(
        name: card.name, jsonData: jsonData);
    final contentHash = ContentHasher.hashString(jsonData);
    // 内容去重检查（DB不可用时降级跳过检查）
    try {
      if (await DatabaseService.contentHashExists(
          'character_cards', contentHash)) {
        return;
      }
    } catch (_) {/* DB unavailable — skip dedup */}
    final now = DateTime.now().toIso8601String();
    await _libraryRepo.saveCharacterCard(
      id: _cardId(card),
      name: card.name,
      jsonData: jsonData,
      source: card.importSource,
      now: now,
      contentHash: contentHash,
    );
    _savedCharacterCards
        .removeWhere((c) => c.name == card.name && c.creator == card.creator);
    _savedCharacterCards.insert(0, card);
    notifyParent();
  }

  Future<void> deleteCharacterCard(int index) async {
    if (index < 0 || index >= _savedCharacterCards.length) return;
    final id = _savedCharacterCards[index].dbId;
    await deleteCharacterCardById(id);
  }

  Future<void> deleteCharacterCardById(String id) async {
    if (id.isEmpty) return;
    await _libraryRepo.deleteCharacterCard(id);
    _savedCharacterCards.removeWhere((c) => c.dbId == id);
    notifyParent();
  }

  Future<void> _migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('saved_character_cards');
    if (json == null || json.isEmpty) return;
    try {
      final list = jsonDecode(json) as List<dynamic>;
      final now = DateTime.now().toIso8601String();
      for (final e in list) {
        final card = CharacterCard.fromJson(e as Map<String, dynamic>);
        try {
          await _libraryRepo.saveCharacterCard(
            id: _cardId(card),
            name: card.name,
            jsonData: jsonEncode(card.toJson()),
            source: card.importSource,
            now: now,
          );
        } catch (e) {
          debugPrint(
              '[CharacterManager] _migrateFromSharedPreferences 保存失败: $e');
        }
      }
      await prefs.remove('saved_character_cards');
    } catch (_) {}
  }

  Future<void> loadCharacterCards() async {
    await _migrateFromSharedPreferences();
    final rows = await _libraryRepo.getCharacterCards();
    final loaded = <CharacterCard>[];
    for (final row in rows) {
      try {
        final json =
            jsonDecode(row['json_data'] as String) as Map<String, dynamic>;
        loaded.add(CharacterCard.fromJson(json).copyWith(
          importSource: row['source'] as String? ?? '',
        ));
      } catch (error) {
        debugPrint('[CharacterManager] 跳过损坏的角色卡 ${row['id']}: $error');
      }
    }
    _savedCharacterCards = loaded;
    notifyParent();
  }
}
