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

  /// Creates a card from a `resources.type` storage value.
  ///
  /// String-based so lightweight callers that only know the legacy type (for
  /// example the adventure wizard part, which cannot import the card model)
  /// can create a card without naming [SettingCardKind].
  Future<SettingCard> createFromType({
    required String type,
    required String name,
    String summary = '',
    String mode = '',
    String content = '',
  }) =>
      create(
        kind: SettingCardKind.fromStorageValue(type),
        name: name,
        summary: summary,
        mode: mode,
        content: content,
      );

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

/// Mirrors legacy library-table writes into lightweight setting cards.
///
/// Phase 5c keeps `worldview_presets` / `character_cards` / `npc_cards` as the
/// write authority for chat, character and worldview saves while the library
/// reads cards. This helper is the one place that maps such a write onto its
/// card, so the two stores cannot drift. It owns no tree, revision or assembly
/// concept.
final class LegacyCardMirror {
  LegacyCardMirror({
    required SettingCardRepository repository,
    String Function()? clock,
  })  : _repository = repository,
        _clock = clock ?? DateTime.now().toIso8601String;

  static const Map<SettingCardKind, String> _sourceTables =
      <SettingCardKind, String>{
    SettingCardKind.worldview: 'worldview_presets',
    SettingCardKind.character: 'character_cards',
    SettingCardKind.npc: 'npc_cards',
  };

  final SettingCardRepository _repository;
  final String Function() _clock;

  /// Stable card id for the legacy row [legacyId] in [kind]'s source table.
  ///
  /// Matches `LegacyResourceMapper.resourceIdFor` so a mirror write updates the
  /// exact card the compatibility migration created, rather than a duplicate.
  static String cardIdFor(SettingCardKind kind, String legacyId) =>
      'res_legacy_${_sourceTables[kind]}_$legacyId';

  /// Creates or updates the mirror card for one saved legacy row.
  ///
  /// An existing card keeps its `createdAt`, editorial `status`, `origin` and
  /// metadata; only the editable body fields and `updatedAt` move. A soft
  /// deleted card is revived so a re-save reappears in the library.
  Future<void> upsertLegacyMirror({
    required SettingCardKind kind,
    required String legacyId,
    required String name,
    String summary = '',
    required String content,
    String mode = '',
  }) async {
    final trimmedId = legacyId.trim();
    if (trimmedId.isEmpty) return;
    final cardId = cardIdFor(kind, trimmedId);
    final existing = await _repository.findById(cardId) ??
        await _repository.findLegacyId(trimmedId, kind: kind);
    final now = _clock();
    await _repository.save(SettingCard(
      id: existing?.id ?? cardId,
      kind: kind,
      name: name,
      summary: summary,
      content: content,
      status: existing?.status ?? SettingCardStatus.draft,
      origin: existing?.origin ?? SettingCardOrigin.legacyRow,
      mode: mode,
      originWorldviewId: existing?.originWorldviewId ?? '',
      metadata: existing?.metadata ?? const <String, Object?>{},
      legacyId: trimmedId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    ));
  }

  /// Soft-deletes the mirror card when its legacy row is deleted.
  Future<void> softDeleteLegacyMirror({
    required SettingCardKind kind,
    required String legacyId,
  }) async {
    final trimmedId = legacyId.trim();
    if (trimmedId.isEmpty) return;
    var card = await _repository.findById(cardIdFor(kind, trimmedId));
    card ??= await _repository.findLegacyId(trimmedId, kind: kind);
    if (card == null) return;
    await _repository.softDelete(card.id, deletedAt: _clock());
  }

  /// Pretty-prints a legacy card JSON payload for the mirror body (lossless).
  static String cardContent(String jsonData) {
    final trimmed = jsonData.trim();
    if (trimmed.isEmpty) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(trimmed));
    } on FormatException {
      return trimmed;
    }
  }

  /// Best-effort summary extracted from a legacy card JSON payload.
  static String cardSummary(String jsonData) {
    try {
      final decoded = jsonDecode(jsonData);
      if (decoded is Map) {
        for (final key in const <String>[
          'description',
          'background',
          'personality',
        ]) {
          final value = decoded[key];
          if (value is String && value.trim().isNotEmpty) return value.trim();
        }
      }
    } on FormatException {
      // Unparseable payload: no summary rather than inventing one.
    }
    return '';
  }

  /// Worldview body: the description plus the detail JSON when it carries data.
  static String worldviewContent({
    required String description,
    String detailJson = '',
  }) {
    final buffer = StringBuffer(description.trim());
    final detail = detailJson.trim();
    if (detail.isNotEmpty && detail != '{}' && detail != '[]') {
      if (buffer.isNotEmpty) {
        buffer.writeln();
        buffer.writeln();
      }
      buffer.writeln('## detail');
      buffer.writeln();
      try {
        final pretty =
            const JsonEncoder.withIndent('  ').convert(jsonDecode(detail));
        buffer.writeln('```json');
        buffer.writeln(pretty);
        buffer.writeln('```');
      } on FormatException {
        buffer.writeln(detail);
      }
    }
    return buffer.toString().trim();
  }
}
