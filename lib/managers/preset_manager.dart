import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/prompt_preset.dart';
import '../models/completion_params.dart';
import '../services/llm_service.dart';
import '../services/repositories/library_repository.dart';

class PresetManager {
  final VoidCallback notifyParent;
  final ILibraryRepository _libraryRepo;

  List<PromptPreset> _presets = [];
  String? _activePresetId;

  List<PromptPreset> get presets => _presets;
  String? get activePresetId => _activePresetId;

  PresetManager({
    required this.notifyParent,
    required ILibraryRepository libraryRepo,
  }) : _libraryRepo = libraryRepo;

  Future<void> _migrateFromSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('prompt_presets');
    if (jsonStr == null || jsonStr.isEmpty) return;
    try {
      final list = jsonDecode(jsonStr) as List<dynamic>;
      for (final e in list) {
        final preset = PromptPreset.fromJson(e as Map<String, dynamic>);
        try {
          await _libraryRepo.savePromptPreset(
            id: preset.id,
            name: preset.name,
            systemPrompt: preset.systemPrompt,
            authorsNote: preset.authorsNote,
            noteDepth: preset.authorsNoteDepth,
            noteFrequency: preset.authorsNoteFrequency,
            now: preset.createdAt?.toIso8601String() ??
                DateTime.now().toIso8601String(),
          );
        } catch (e) {
          debugPrint('[PresetManager] _migrateFromSharedPreferences 保存失败: $e');
        }
      }
      await prefs.remove('prompt_presets');
    } catch (_) {}
  }

  Future<void> loadPresets() async {
    await _migrateFromSharedPreferences();
    final rows = await _libraryRepo.getPromptPresets();
    if (rows.isEmpty) {
      _presets = _defaultPresets();
      await savePresets();
    } else {
      _presets = rows.map((row) {
        return PromptPreset(
          id: row['id'] as String,
          name: row['name'] as String,
          systemPrompt: row['system_prompt'] as String,
          authorsNote: row['authors_note'] as String? ?? '',
          authorsNoteDepth: row['note_depth'] as int? ?? 3,
          authorsNoteFrequency: row['note_frequency'] as int? ?? 3,
          createdAt: DateTime.parse(row['created_at'] as String),
        );
      }).toList();
    }
    final prefs = await SharedPreferences.getInstance();
    _activePresetId = prefs.getString('active_preset_id');
    notifyParent();
  }

  Future<void> savePresets() async {
    for (final p in _presets) {
      try {
        await _libraryRepo.savePromptPreset(
          id: p.id,
          name: p.name,
          systemPrompt: p.systemPrompt,
          authorsNote: p.authorsNote,
          noteDepth: p.authorsNoteDepth,
          noteFrequency: p.authorsNoteFrequency,
          now: p.createdAt?.toIso8601String() ??
              DateTime.now().toIso8601String(),
        );
      } catch (e) {
        debugPrint('[PresetManager] savePresets 保存失败 (${p.name}): $e');
      }
    }
  }

  Future<void> addPreset(PromptPreset preset) async {
    _presets.add(preset);
    await savePresets();
    notifyParent();
  }

  Future<void> updatePreset(PromptPreset preset) async {
    final idx = _presets.indexWhere((p) => p.id == preset.id);
    if (idx >= 0) _presets[idx] = preset;
    await savePresets();
    notifyParent();
  }

  Future<void> deletePreset(String id) async {
    _presets.removeWhere((p) => p.id == id);
    if (_activePresetId == id) _activePresetId = null;
    try {
      await _libraryRepo.deletePromptPreset(id);
    } catch (e) {
      debugPrint('[PresetManager] deletePreset 失败: $e');
    }
    notifyParent();
  }

  Future<void> applyPreset(
    PromptPreset preset, {
    required Future<void> Function(String) setSystemPrompt,
    required Future<void> Function(String) setAuthorsNote,
    required Future<void> Function(int, int) setAuthorsNoteConfig,
    required void Function(TranslationMode) setTranslationMode,
    required Future<void> Function(LLMProvider) setProvider,
    required Future<void> Function(String) setModel,
    required Future<void> Function(CompletionParams) onSetCompletionParams,
  }) async {
    await setSystemPrompt(preset.systemPrompt);
    await setAuthorsNote(preset.authorsNote);
    await setAuthorsNoteConfig(
        preset.authorsNoteDepth, preset.authorsNoteFrequency);
    setTranslationMode(preset.translationMode);
    if (preset.provider != null) await setProvider(preset.provider!);
    if (preset.model != null) await setModel(preset.model!);
    if (preset.completionParams != null) {
      await onSetCompletionParams(preset.completionParams!);
    }

    final prefs = await SharedPreferences.getInstance();
    _activePresetId = preset.id;
    await prefs.setString('active_preset_id', preset.id);
    notifyParent();
  }

  String importPresetsFromJson(String jsonStr) {
    final imported = PromptPreset.importFromJson(jsonStr);
    if (imported.isEmpty) return '导入失败：无法解析预设 JSON';
    _presets.addAll(imported);
    savePresets();
    notifyParent();
    return '成功导入 ${imported.length} 个预设';
  }

  String exportPresetsToJson() => PromptPreset.exportAllToJson(_presets);

  static List<PromptPreset> _defaultPresets() => [];
}
