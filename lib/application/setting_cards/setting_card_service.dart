import 'dart:convert';

import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import '../llm/llm_gateway.dart';

/// Raised when a card cannot be generated.
class SettingCardGenerationException implements Exception {
  const SettingCardGenerationException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'SettingCardGenerationException: $message';
}

/// Lightweight application service for setting cards.
///
/// Owns the whole lifecycle the new editor needs: list, create, save, delete
/// and one single-shot generation per card. It never touches the retired tree.
final class SettingCardService {
  SettingCardService({
    required SettingCardRepository repository,
    LlmGateway? gateway,
    String Function()? clock,
    String Function()? idGenerator,
  })  : _repository = repository,
        _gateway = gateway,
        _clock = clock ?? _defaultClock,
        _idGenerator = idGenerator ?? _defaultIdGenerator;

  static const Set<String> _documentMetaKeys = <String>{
    'id',
    'name',
    'status',
    'format_version',
    'mode',
    'source',
    'source_id',
    'created_at',
    'updated_at',
  };

  static String _defaultClock() => DateTime.now().toIso8601String();

  static String _defaultIdGenerator() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'sc_$stamp';
  }

  final SettingCardRepository _repository;
  final LlmGateway? _gateway;
  final String Function() _clock;
  final String Function() _idGenerator;

  bool get canGenerate => _gateway?.isConfigured ?? false;

  Future<List<SettingCard>> list({
    SettingCardKind? kind,
    String mode = '',
  }) async {
    final cards = await _repository.list(kind: kind);
    if (mode.isEmpty) return cards;
    return cards
        .where((card) => card.mode.isEmpty || card.mode == mode)
        .toList(growable: false);
  }

  Future<SettingCard?> find(String id, {String? legacyId}) async {
    final direct = await _repository.findById(id);
    if (direct != null) return direct;
    if (legacyId == null || legacyId.isEmpty) return null;
    return _repository.findLegacyId(legacyId);
  }

  Future<SettingCard> create({
    required SettingCardKind kind,
    required String name,
    String summary = '',
    String mode = '',
    String content = '',
  }) async {
    final now = _clock();
    final card = SettingCard(
      id: _idGenerator(),
      kind: kind,
      name: name,
      summary: summary,
      content: content,
      mode: mode,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.save(card);
    return card;
  }

  Future<SettingCard> save({
    required String id,
    required String name,
    required String summary,
    required String content,
  }) async {
    final existing = await _repository.findById(id);
    if (existing == null) {
      throw StateError('Setting card not found: $id');
    }
    final updated = existing.copyWith(
      name: name,
      summary: summary,
      content: content,
      updatedAt: _clock(),
    );
    await _repository.save(updated);
    return updated;
  }

  Future<void> delete(String id) =>
      _repository.softDelete(id, deletedAt: _clock());

  /// Runs exactly one generation for [id] and merges the result into the card.
  ///
  /// [instruction] is the user's free-form description; an empty instruction
  /// tells the model to expand the card's current content instead.
  Future<SettingCard> generate({
    required String id,
    required String instruction,
    void Function(int currentStage, int totalStages, String stageName)?
        onProgress,
  }) async {
    final gateway = _gateway;
    if (gateway == null || !gateway.isConfigured) {
      throw const SettingCardGenerationException('AI 尚未配置');
    }
    final card = await _repository.findById(id);
    if (card == null) {
      throw SettingCardGenerationException('设定卡不存在: $id');
    }
    final source =
        instruction.trim().isEmpty ? card.content.trim() : instruction.trim();
    if (source.isEmpty) {
      throw const SettingCardGenerationException('请先填写生成要求');
    }

    final Map<String, Object?> generated;
    try {
      generated = switch (card.kind) {
        SettingCardKind.worldview => await gateway.generateDetailedWorldview(
            source,
            onProgress: onProgress == null
                ? null
                : (progress) {
                    final done = progress.completedQuestions;
                    final total = progress.totalQuestions;
                    final label = '$done / $total';
                    onProgress(
                      progress.completedQuestions,
                      progress.totalQuestions,
                      label,
                    );
                  },
          ),
        SettingCardKind.character ||
        SettingCardKind.npc =>
          await gateway.generateDetailedResourceCharacter(
            source: source,
            onProgress: onProgress,
          ),
      };
    } catch (error) {
      throw SettingCardGenerationException('生成失败', cause: error);
    }

    final content = renderGeneratedDocument(generated);
    if (content.trim().isEmpty) {
      throw const SettingCardGenerationException('模型未返回可用内容');
    }
    final generatedName = generated['name']?.toString().trim() ?? '';
    final generatedSummary = generated['description']?.toString().trim() ?? '';
    final updated = card.copyWith(
      name: card.name.trim().isEmpty && generatedName.isNotEmpty
          ? generatedName
          : card.name,
      summary: card.summary.trim().isEmpty && generatedSummary.isNotEmpty
          ? generatedSummary
          : card.summary,
      content: content,
      updatedAt: _clock(),
    );
    await _repository.save(updated);
    return updated;
  }

  /// Renders a generated structured payload into the single document.
  ///
  /// Prose values become a level-two heading section; structured values stay
  /// lossless as a JSON block instead of being flattened into one run-on line.
  static String renderGeneratedDocument(Map<String, Object?> data) {
    final buffer = StringBuffer();
    for (final entry in data.entries) {
      final key = entry.key;
      if (_documentMetaKeys.contains(key)) continue;
      final value = entry.value;
      if (value == null) continue;
      if (value is String) {
        final text = value.trim();
        if (text.isEmpty) continue;
        _block(buffer, '## $key');
        _block(buffer, text);
      } else if (value is num || value is bool) {
        _block(buffer, '## $key');
        _block(buffer, value.toString());
      } else if (value is Map || value is List) {
        if (value is Map && value.isEmpty) continue;
        if (value is List && value.isEmpty) continue;
        _block(buffer, '## $key');
        final encoded = const JsonEncoder.withIndent('  ').convert(value);
        _block(buffer, '```json\n$encoded\n```');
      }
    }
    return buffer.toString().trim();
  }

  static void _block(StringBuffer buffer, String text) {
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.writeln(text);
    buffer.writeln();
  }
}
