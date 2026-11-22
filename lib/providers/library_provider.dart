import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/persona.dart';
import '../models/character_card.dart';
import '../models/prompt_preset.dart';
import '../models/adventure_config.dart';
import '../services/repositories/library_repository.dart';
import '../managers/character_manager.dart';
import '../managers/preset_manager.dart' as pm;

/// 内容库 Provider
/// 拥有：角色卡、提示词预设、世界观预设、人格化身
class LibraryProvider extends ChangeNotifier {
  final ILibraryRepository _libraryRepo;

  late final CharacterManager _charMgr;
  late final pm.PresetManager _presetMgr;

  List<Persona> _personas = [];
  String? _activePersonaId;

  LibraryProvider({required ILibraryRepository libraryRepo})
      : _libraryRepo = libraryRepo {
    _charMgr = CharacterManager(
      notifyParent: notifyListeners,
      libraryRepo: _libraryRepo,
    );
    _presetMgr = pm.PresetManager(
      notifyParent: notifyListeners,
      libraryRepo: _libraryRepo,
    );
  }

  // ─── Getters ───
  List<CharacterCard> get savedCharacterCards => _charMgr.savedCharacterCards;
  List<PromptPreset> get presets => _presetMgr.presets;
  String? get activePresetId => _presetMgr.activePresetId;
  List<Persona> get personas => _personas;
  Persona? get activePersona {
    if (_activePersonaId == null || _personas.isEmpty) return null;
    try {
      return _personas.firstWhere((p) => p.id == _activePersonaId);
    } catch (_) {
      return null;
    }
  }

  // ─── Personas ───

  Future<void> loadPersonas() async {
    final rows = await _libraryRepo.getPersonas();
    _personas = rows.map((r) {
      final stored = Persona.fromJson(jsonDecode(r['json_data'] as String));
      return stored.copyWith(
        id: r['id'] as String,
        name: r['name'] as String,
      );
    }).toList();
    // 回退：DB 中无 Persona 时，内存中默认为冒险者（与 SharedPreferences 旧行为兼容）
    if (_personas.isEmpty) {
      _personas = [
        Persona(name: '冒险者', description: '一名勇敢的冒险者', isDefault: true),
      ];
    }
    notifyListeners();
  }

  Future<void> addPersona(Persona p) async {
    final persona = p.id.isNotEmpty
        ? p
        : p.copyWith(id: DateTime.now().millisecondsSinceEpoch.toString());
    final id = persona.id;
    _personas.add(persona);
    await _libraryRepo.savePersona(
      id: id,
      name: persona.name,
      jsonData: jsonEncode(persona.toJson()),
      now: DateTime.now().toIso8601String(),
    );
    notifyListeners();
  }

  Future<void> updatePersona(Persona p) async {
    final idx = _personas.indexWhere((e) => e.id == p.id);
    if (idx >= 0) _personas[idx] = p;
    await _libraryRepo.savePersona(
      id: p.id,
      name: p.name,
      jsonData: jsonEncode(p.toJson()),
      now: DateTime.now().toIso8601String(),
    );
    notifyListeners();
  }

  Future<void> deletePersona(String id) async {
    _personas.removeWhere((p) => p.id == id);
    if (_activePersonaId == id) _activePersonaId = null;
    await _libraryRepo.deletePersona(id);
    notifyListeners();
  }

  Future<void> setActivePersona(String? id) async {
    _activePersonaId = id;
    notifyListeners();
  }

  // ─── Character Cards ───

  Future<String> importCharacterCardJson(String jsonStr) =>
      _charMgr.importCharacterCardJson(jsonStr);

  AdventureConfig buildConfigFromCard(CharacterCard card) =>
      _charMgr.buildConfigFromCard(card);

  void applyCharacterCard(CharacterCard card) =>
      _charMgr.applyCharacterCard(card);

  Future<void> saveCharacterCard(CharacterCard card) async {
    await _charMgr.saveCharacterCard(card);
    notifyListeners();
  }

  Future<void> deleteCharacterCard(int id) async {
    await _charMgr.deleteCharacterCard(id);
    notifyListeners();
  }

  Future<void> deleteCharacterCardById(String id) async {
    await _charMgr.deleteCharacterCardById(id);
    notifyListeners();
  }

  Future<void> loadCharacterCards() => _charMgr.loadCharacterCards();

  // ─── Prompt Presets ───

  Future<void> loadPresets() => _presetMgr.loadPresets();
  Future<void> savePresets() => _presetMgr.savePresets();

  Future<void> addPreset(PromptPreset p) async {
    await _presetMgr.addPreset(p);
    notifyListeners();
  }

  Future<void> updatePreset(PromptPreset p) async {
    await _presetMgr.updatePreset(p);
    notifyListeners();
  }

  Future<void> deletePreset(String id) async {
    await _presetMgr.deletePreset(id);
    notifyListeners();
  }

  // applyPreset is handled directly by ChatProvider facade
  // since it needs cross-provider callbacks
  pm.PresetManager get presetMgr => _presetMgr;

  String importPresetsFromJson(String json) =>
      _presetMgr.importPresetsFromJson(json);

  String exportPresetsToJson() => _presetMgr.exportPresetsToJson();
}
