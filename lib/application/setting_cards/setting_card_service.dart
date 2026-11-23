import 'dart:convert';
import 'dart:developer' as developer;

import '../../domain/setting_cards/setting_card.dart';
import '../../domain/setting_cards/setting_card_repository.dart';
import '../../models/generation_stage_progress.dart';
import '../../models/generation_task_handle.dart';
import '../llm/llm_gateway.dart';
import 'setting_card_context_budgeter.dart';
import 'setting_card_markdown_parser.dart';
import 'setting_card_reference_input.dart';

/// Raised when a card cannot be generated.
class SettingCardGenerationException implements Exception {
  const SettingCardGenerationException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'SettingCardGenerationException: $message';
}

/// Raised when the user cancelled generation before the result was persisted.
///
/// The cancellation check runs after the model returned but before any snapshot
/// or body is written, so a cancelled request leaves the card exactly as it was.
/// UI layers should treat this as an informational cancellation, not a failure.
class SettingCardGenerationCancelledException implements Exception {
  const SettingCardGenerationCancelledException();

  @override
  String toString() => 'SettingCardGenerationCancelledException';
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
    Future<List<Map<String, String>>> Function(String cardId)? relationLoader,
  })  : _repository = repository,
        _gateway = gateway,
        _clock = clock ?? _defaultClock,
        _idGenerator = idGenerator ?? _defaultIdGenerator,
        _relationLoader = relationLoader;

  /// Metadata key holding the body the last generation overwrote.
  ///
  /// Regeneration is destructive for a hand-edited card, so one generation
  /// keeps the immediately previous body (plus its structured payload) here.
  /// Only the newest snapshot is kept: a second generation replaces it, which
  /// deliberately limits undo to one level instead of growing a revision list.
  static const String previousSnapshotKey = 'previous_content_snapshot';

  static String _defaultClock() => DateTime.now().toIso8601String();

  static String _defaultIdGenerator() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'sc_$stamp';
  }

  static const SettingCardContextBudgeter _budgeter =
      SettingCardContextBudgeter();
  static const SettingCardMarkdownParser _parser = SettingCardMarkdownParser();

  final SettingCardRepository _repository;
  final LlmGateway? _gateway;
  final String Function() _clock;
  final String Function() _idGenerator;
  final Future<List<Map<String, String>>> Function(String cardId)?
      _relationLoader;

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
    String originWorldviewId = '',
  }) =>
      create(
        kind: SettingCardKind.fromStorageValue(type),
        name: name,
        summary: summary,
        mode: mode,
        content: content,
        originWorldviewId: originWorldviewId,
      );

  Future<SettingCard> create({
    required SettingCardKind kind,
    required String name,
    String summary = '',
    String mode = '',
    String content = '',
    String originWorldviewId = '',
  }) async {
    final now = _clock();
    final card = SettingCard(
      id: _idGenerator(),
      kind: kind,
      name: name,
      summary: summary,
      content: content,
      mode: mode,
      originWorldviewId: originWorldviewId,
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

  /// Restores the body [generate] overwrote most recently.
  ///
  /// Returns null when the card never had a snapshot, or the snapshot carries
  /// no body, without touching storage. A successful restore consumes the
  /// snapshot so the same overwrite cannot be undone twice.
  ///
  /// Payload keys behave symmetrically: a key present in the snapshot is put
  /// back, a key absent from it is removed. Keeping the newer payload next to
  /// an older body would leave the card internally inconsistent.
  Future<SettingCard?> restorePreviousSnapshot(String id) async {
    final card = await _repository.findById(id);
    if (card == null) {
      throw SettingCardGenerationException('设定卡不存在: $id');
    }
    final snapshot = _decodeSnapshot(card.metadata[previousSnapshotKey]);
    final content = snapshot?['content']?.toString() ?? '';
    if (snapshot == null || content.trim().isEmpty) return null;

    final metadata = Map<String, Object?>.from(card.metadata)
      ..remove(previousSnapshotKey);
    for (final key in _snapshotPayloadKeys) {
      if (snapshot.containsKey(key)) {
        metadata[key] = snapshot[key];
      } else {
        metadata.remove(key);
      }
    }
    final updated = card.copyWith(
      summary: snapshot['summary']?.toString() ?? '',
      content: content,
      metadata: metadata,
      updatedAt: _clock(),
    );
    await _repository.save(updated);
    return updated;
  }

  /// Soft-deletes a card whose body is still empty.
  ///
  /// The create page may persist a draft before the first generation; when
  /// that generation fails, this cleans up the orphan without ever touching a
  /// card that holds user content. A missing id is a no-op so callers do not
  /// have to branch on cleanup.
  Future<void> discardEmptyDraft(String id) async {
    final card = await _repository.findById(id);
    if (card == null) return;
    if (card.content.trim().isNotEmpty) return;
    await _repository.softDelete(id, deletedAt: _clock());
  }

  /// Runs exactly one generation for [id] and merges the result into the card.
  ///
  /// [instruction] is the user's free-form description; an empty instruction
  /// tells the model to expand the card's current content instead.
  ///
  /// Context is deliberately bounded before it reaches the gateway: the
  /// gateway has one `source` channel, so oversized reference material and
  /// worldviews are reduced to the most relevant passages instead of being
  /// dropped or flooding the prompt.
  ///
  /// When the card already holds a body, it is snapshotted under
  /// [previousSnapshotKey] before the generated document replaces it. A
  /// failed generation throws before saving, so it never writes a snapshot.
  Future<SettingCard> generate({
    required String id,
    required String instruction,
    String worldview = '',
    List<Map<String, String>> associatedCharacters = const [],
    int? targetTotalCharacters,
    SettingCardReferenceInput? reference,
    GenerationTaskHandle? taskHandle,
    void Function(GenerationStageProgress progress)? onProgress,
  }) async {
    final gateway = _gateway;
    if (gateway == null || !gateway.isConfigured) {
      throw const SettingCardGenerationException('AI 尚未配置');
    }
    final card = await _repository.findById(id);
    if (card == null) {
      throw SettingCardGenerationException('设定卡不存在: $id');
    }
    var source =
        instruction.trim().isEmpty ? card.content.trim() : instruction.trim();
    if (source.isEmpty) {
      throw const SettingCardGenerationException('请先填写生成要求');
    }

    final String worldviewContext;
    var linkedCharacters = const <Map<String, String>>[];
    try {
      final referenceText = await _resolveReference(reference);
      if (referenceText.isNotEmpty) {
        final bounded = _budgeter.selectReference(
          source: source,
          reference: referenceText,
        );
        if (bounded.isNotEmpty) {
          source = '$source\n\n【参考材料（用户提供，可用于创作）】\n$bounded';
        }
      }

      if (card.kind == SettingCardKind.worldview) {
        worldviewContext = '';
      } else {
        final rawWorldview = worldview.trim().isNotEmpty
            ? worldview
            : await _loadOriginWorldview(card);
        worldviewContext = rawWorldview.isEmpty
            ? ''
            : _budgeter.selectWorldview(
                source: source,
                worldview: _budgetableWorldview(rawWorldview),
              );
        linkedCharacters =
            _budgeter.summarizeAssociatedCharacters(associatedCharacters);
        if (associatedCharacters.isEmpty) {
          final saved = await _loadSavedRelations(card.id);
          if (saved.isNotEmpty) {
            linkedCharacters = _budgeter.summarizeAssociatedCharacters(saved);
            source = '$source\n\n以下角色关系已由用户确认，不可改写';
          }
        }
      }

      // Bound the final source once, after references and confirmed relations
      // are appended, so a downstream policy cannot silently re-truncate and
      // drop the tail the user asked us to keep.
      source = _budgeter.boundInstruction(source);
    } catch (error) {
      if (error is SettingCardGenerationException) rethrow;
      throw SettingCardGenerationException('读取生成上下文失败', cause: error);
    }

    final Map<String, Object?> generated;
    try {
      generated = switch (card.kind) {
        SettingCardKind.worldview => await gateway.generateDetailedWorldview(
            source,
            targetTotalCharacters: targetTotalCharacters,
            taskHandle: taskHandle,
            onProgress: onProgress == null
                ? null
                : (progress) {
                    final label = progress.partialText.trim();
                    onProgress(GenerationStageProgress(
                      stage: progress.completedQuestions,
                      totalStages: progress.totalQuestions,
                      stageName: label.isEmpty ? '世界观生成' : label,
                      currentCharacters: progress.currentCharacters,
                      targetCharacters: progress.targetCharacters,
                      supplementRound: progress.supplementRound,
                    ));
                  },
          ),
        SettingCardKind.character ||
        SettingCardKind.npc =>
          await gateway.generateDetailedResourceCharacter(
            source: source,
            worldview: worldviewContext,
            associatedCharacters: linkedCharacters,
            targetTotalCharacters: targetTotalCharacters,
            isNpc: card.kind == SettingCardKind.npc,
            taskHandle: taskHandle,
            // The gateway reports structured stage progress when it can; the
            // legacy three-argument callback is wrapped for gateways that only
            // emit the older shape.
            onProgress: onProgress == null
                ? null
                : (stage, totalStages, stageName) => onProgress(
                      GenerationStageProgress(
                        stage: stage,
                        totalStages: totalStages,
                        stageName: stageName,
                      ),
                    ),
            onStageProgress: onProgress,
          ),
      };
    } catch (error) {
      // A cancelled request is an expected outcome, not a model failure: keep
      // the type distinct so the UI can report it as a cancellation.
      if (taskHandle?.isCancelled ?? false) {
        throw const SettingCardGenerationCancelledException();
      }
      if (error is SettingCardGenerationException) rethrow;
      throw SettingCardGenerationException('生成失败', cause: error);
    }

    final content = renderGeneratedDocument(generated, kind: card.kind);
    if (content.trim().isEmpty) {
      throw const SettingCardGenerationException('模型未返回可用内容');
    }
    // The model may finish just after the user cancels. Check here, before the
    // snapshot and save, so a cancelled generation never overwrites the edited
    // body with a partial result.
    if (taskHandle?.isCancelled ?? false) {
      throw const SettingCardGenerationCancelledException();
    }
    final generatedName = generated['name']?.toString().trim() ?? '';
    final generatedSummary = generated['description']?.toString().trim() ?? '';
    final now = _clock();
    final metadata = _metadataWithPayload(card, generated);
    // Snapshotting after the new payload is merged keeps the old body and its
    // old payload together under one key while the new payload stays at the
    // metadata top level.
    if (card.content.trim().isNotEmpty) {
      metadata[previousSnapshotKey] = _contentSnapshot(card, now);
    }
    final updated = card.copyWith(
      name: card.name.trim().isEmpty && generatedName.isNotEmpty
          ? generatedName
          : card.name,
      summary: card.summary.trim().isEmpty && generatedSummary.isNotEmpty
          ? generatedSummary
          : card.summary,
      content: content,
      metadata: metadata,
      updatedAt: now,
    );
    await _repository.save(updated);
    return updated;
  }

  /// Resolves a user-selected reference into prompt text.
  ///
  /// An `existingCard` reference is re-read from the repository at generation
  /// time so a stale UI snapshot cannot freeze an older body into the new card.
  Future<String> _resolveReference(SettingCardReferenceInput? reference) async {
    if (reference == null) return '';
    switch (reference.mode) {
      case SettingCardReferenceMode.paste:
        return reference.text.trim();
      case SettingCardReferenceMode.file:
        final body = reference.text.trim();
        if (body.isEmpty) return '';
        final label = reference.label.trim();
        return label.isEmpty ? body : '文件：$label\n$body';
      case SettingCardReferenceMode.existingCard:
        final sourceId = reference.sourceCardId.trim();
        if (sourceId.isEmpty) {
          throw const SettingCardGenerationException('引用设定卡时缺少卡片 id');
        }
        final target = await _repository.findById(sourceId) ??
            await _repository.findLegacyId(sourceId);
        if (target == null || target.isDeleted) {
          throw SettingCardGenerationException('引用的设定卡不存在: $sourceId');
        }
        final body = target.content.trim();
        final name = target.name.trim();
        return name.isEmpty ? body : '设定卡：$name\n$body';
    }
  }

  /// Loads the card's origin worldview when the caller did not pass one.
  ///
  /// Missing or deleted origin cards degrade to "no worldview context" rather
  /// than failing generation: the card may have been migrated without its
  /// worldview row, and the user can still generate a standalone character.
  Future<String> _loadOriginWorldview(SettingCard card) async {
    final originId = card.originWorldviewId.trim();
    if (originId.isEmpty) return '';
    final origin = await _repository.findById(originId) ??
        await _repository.findLegacyId(originId);
    if (origin == null || origin.isDeleted) return '';
    if (origin.kind != SettingCardKind.worldview) return '';
    return origin.content;
  }

  /// Loads the card's saved relationships as generation context.
  ///
  /// Relationship metadata is optional and repository-backed, so a missing
  /// loader or a read failure degrades to "no saved relations" instead of
  /// blocking generation. Callers that already passed explicit relations never
  /// reach this method.
  Future<List<Map<String, String>>> _loadSavedRelations(String cardId) async {
    final loader = _relationLoader;
    if (loader == null) return const <Map<String, String>>[];
    try {
      return await loader(cardId);
    } catch (error) {
      // Relationship storage is supplementary context; generation can proceed
      // without it rather than surfacing an unrelated storage failure. Keep the
      // failure type visible so a broken loader stays diagnosable.
      developer.log(
        'relation context unavailable: ${error.runtimeType}',
        name: 'SettingCardService',
      );
      return const <Map<String, String>>[];
    }
  }

  /// Converts a markdown card body into the structured detail JSON the
  /// budgeter scores module by module.
  ///
  /// A body without module sections (plain prose) stays as-is and falls back
  /// to the budgeter's linear truncation.
  String _budgetableWorldview(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.startsWith('{')) return trimmed;
    final detail = _parser.parseWorldviewDetailFromContent(trimmed);
    return detail == null ? trimmed : jsonEncode(detail);
  }

  /// Metadata keys that carry a payload and therefore travel with a snapshot.
  static const List<String> _snapshotPayloadKeys = <String>[
    SettingCardMarkdownParser.structuredPayloadKey,
    SettingCardMarkdownParser.detailJsonKey,
  ];

  /// Captures the parts of [card] a regeneration is about to replace.
  ///
  /// Payload keys are copied only when present, so a snapshot never invents an
  /// empty payload that [restorePreviousSnapshot] would then write back.
  Map<String, Object?> _contentSnapshot(SettingCard card, String savedAt) {
    final snapshot = <String, Object?>{
      'content': card.content,
      'summary': card.summary,
      'saved_at': savedAt,
    };
    for (final key in _snapshotPayloadKeys) {
      final value = card.metadata[key];
      if (value != null) snapshot[key] = value;
    }
    return snapshot;
  }

  /// Normalizes a stored snapshot into a plain key/value map.
  ///
  /// A database round-trip yields a map with untyped keys, so the restore path
  /// must not rely on the in-memory map type.
  static Map<String, Object?>? _decodeSnapshot(Object? raw) {
    if (raw is! Map) return null;
    return <String, Object?>{
      for (final entry in raw.entries) entry.key.toString(): entry.value,
    };
  }

  /// Persists the raw structured payload next to the rendered document.
  ///
  /// The document alone loses field types when a user edits prose; keeping the
  /// payload lets the adventure snapshot rebuild the full character/worldview
  /// shape without re-calling the model.
  Map<String, Object?> _metadataWithPayload(
    SettingCard card,
    Map<String, Object?> generated,
  ) {
    final metadata = Map<String, Object?>.from(card.metadata);
    if (card.kind == SettingCardKind.worldview) {
      final detail = generated[SettingCardMarkdownParser.detailJsonKey];
      final decoded = detail is String ? _tryDecodeMap(detail) : detail;
      if (decoded is Map) {
        metadata[SettingCardMarkdownParser.detailJsonKey] = _carryDefinitions(
            decoded, card.metadata[SettingCardMarkdownParser.detailJsonKey]);
      } else if (generated['modules'] is Map) {
        // Older payloads expose modules at the top level; keep the structured
        // original under detail_json so the rendered document stays a view.
        metadata[SettingCardMarkdownParser.detailJsonKey] = _carryDefinitions(
          <String, Object?>{
            'format_version': 2,
            'mode': 'detailed',
            'modules': generated['modules'],
          },
          card.metadata[SettingCardMarkdownParser.detailJsonKey],
        );
      }
    } else {
      metadata[SettingCardMarkdownParser.structuredPayloadKey] =
          _carryDefinitions(generated,
              card.metadata[SettingCardMarkdownParser.structuredPayloadKey]);
    }
    return metadata;
  }

  /// Keeps the card's monitoring definitions across a regeneration.
  ///
  /// Definitions are authored metadata, not model output: a fresh document
  /// replaces the prose, but silently dropping the user's monitored stats would
  /// break the tracked-state chain the card already declared.
  static Map<String, Object?> _carryDefinitions(
    Map<dynamic, dynamic> next,
    Object? previous,
  ) {
    final result = <String, Object?>{
      for (final entry in next.entries) entry.key.toString(): entry.value,
    };
    final old = previous is String ? _tryDecodeMap(previous) : previous;
    if (result.containsKey('tracked_state_definitions') || old is! Map) {
      return result;
    }
    final carried = old['tracked_state_definitions'];
    if (carried is List && carried.isNotEmpty) {
      result['tracked_state_definitions'] = carried;
    }
    return result;
  }

  static Map<String, dynamic>? _tryDecodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // A non-JSON detail string carries no structured payload.
    }
    return null;
  }

  /// Renders a generated payload into the single human-readable document.
  ///
  /// The document is the editor's primary view, so it must read like a setting
  /// document: no JSON fences, no raw objects. Structured originals stay in
  /// metadata and the parser reads the rendered Markdown back.
  static String renderGeneratedDocument(
    Map<String, Object?> data, {
    SettingCardKind? kind,
  }) {
    final resolved = kind ?? _inferKind(data);
    return resolved == SettingCardKind.worldview
        ? SettingCardDocumentRenderer.renderWorldview(data)
        : SettingCardDocumentRenderer.renderCharacter(data);
  }

  /// Infers the document family when the caller did not supply a card kind.
  static SettingCardKind _inferKind(Map<String, Object?> data) {
    if (data.containsKey(SettingCardMarkdownParser.detailJsonKey)) {
      return SettingCardKind.worldview;
    }
    if (data.containsKey('modules') &&
        !data.containsKey('world_profile') &&
        !data.containsKey('personality')) {
      return SettingCardKind.worldview;
    }
    return SettingCardKind.character;
  }
}

/// Renders generated / mirrored payloads as readable Chinese Markdown.
///
/// One renderer serves generation and legacy mirroring so a card never carries
/// two different document shapes for the same data. The parser's Chinese
/// section mappings mirror these titles exactly.
final class SettingCardDocumentRenderer {
  const SettingCardDocumentRenderer._();

  /// Module key to the product's standard Chinese section title.
  static const Map<String, String> worldviewModuleTitles = <String, String>{
    'overview': '概览',
    'world_rules': '规则与边界',
    'world_state': '当前世界现状',
    'locations': '地点与地理',
    'factions': '势力与组织',
    'customs_and_life': '风俗与生活',
    'timeline': '历史与时间线',
    'glossary': '术语表',
    'creative_constraints': '创作约束',
  };

  static const List<String> _worldviewModuleOrder = <String>[
    'overview',
    'world_rules',
    'world_state',
    'locations',
    'factions',
    'customs_and_life',
    'timeline',
    'glossary',
    'creative_constraints',
  ];

  static const List<String> _nameKeys = <String>[
    'name',
    'title',
    'term',
    'event',
    'label',
  ];
  static const List<String> _descriptionKeys = <String>[
    'description',
    'summary',
    'content',
    'detail',
  ];

  /// Renders a worldview payload.
  ///
  /// Module values may be prose, a module map or a list of entries; every shape
  /// becomes readable text. The top-level description only fills an overview
  /// that the modules do not supply, so it is never duplicated.
  static String renderWorldview(Map<String, Object?> data) {
    final modules = _worldviewModules(data);
    final description = _text(data['description']);
    final overview = _moduleText(modules['overview']);
    final overviewText = overview.isNotEmpty ? overview : description;

    final sections = <(String, String)>[];
    for (final key in _worldviewModuleOrder) {
      if (!modules.containsKey(key)) continue;
      final text = key == 'overview' ? overviewText : _moduleText(modules[key]);
      if (text.isEmpty) continue;
      sections.add((worldviewModuleTitles[key] ?? key, text));
    }
    if (!modules.containsKey('overview') && overviewText.isNotEmpty) {
      sections.insert(0, (worldviewModuleTitles['overview']!, overviewText));
    }
    for (final entry in modules.entries) {
      if (_worldviewModuleOrder.contains(entry.key)) continue;
      final text = _moduleText(entry.value);
      if (text.isEmpty) continue;
      sections.add((entry.key, text));
    }
    return _joinSections(sections);
  }

  /// Renders a character / NPC payload into the fixed document layout.
  static String renderCharacter(Map<String, Object?> data) {
    final sections = <(String, String)>[];

    final basic = <String, String>{};
    _putField(basic, '姓名', data['name']);
    _putField(basic, '性别', data['gender']);
    _putField(basic, '年龄', data['age']);
    _putField(basic, '职业身份', data['profession']);
    _putField(basic, '人物原型', data['archetype']);
    if (basic.isNotEmpty) sections.add(('基础信息', _bullets(basic)));

    _addProse(sections, '性格与心理', _text(data['personality']));

    final appearance = <String, String>{};
    _putField(appearance, '外貌', data['appearance']);
    _putField(appearance, '体态', data['bodyDescription']);
    if (appearance.isNotEmpty) sections.add(('外貌与体态', _bullets(appearance)));

    final description = _text(data['description']);
    final background = _text(data['background']);
    final backgroundText = description.isEmpty
        ? background
        : (background.isEmpty || background == description
            ? description
            : '$description\n\n$background');
    _addProse(sections, '背景经历', backgroundText);

    final profileFields = _worldProfileFields(data['world_profile']);
    if (profileFields.isNotEmpty) {
      sections.add(('世界定位与动机', _bullets(profileFields)));
    }

    final ability = <String, String>{};
    _putField(ability, '能力', data['ability']);
    _putField(ability, '弱点', data['weakness']);
    _putField(ability, '装备', data['equipment']);
    if (ability.isNotEmpty) sections.add(('能力与装备', _bullets(ability)));

    final roleplay = <String, String>{};
    _putField(roleplay, '说话风格', data['speaking_style']);
    _putField(roleplay, '角色弧光', data['character_arc']);
    _putField(roleplay, '开场首句', data['first_mes']);
    _putField(roleplay, '对话示例', data['mes_example']);
    if (roleplay.isNotEmpty) sections.add(('扮演与对话风格', _bullets(roleplay)));

    final attributes = _customAttributeLines(data['custom_attributes']);
    if (attributes.isNotEmpty) {
      sections.add(('自定义属性', attributes));
    }
    return _joinSections(sections);
  }

  static String _joinSections(List<(String, String)> sections) {
    final buffer = StringBuffer();
    for (final (title, body) in sections) {
      final text = body.trim();
      if (text.isEmpty) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('## $title');
      buffer.writeln();
      buffer.writeln(text);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  static void _addProse(
    List<(String, String)> sections,
    String title,
    String body,
  ) {
    if (body.trim().isEmpty) return;
    sections.add((title, body.trim()));
  }

  static void _putField(Map<String, String> fields, String label, Object? raw) {
    final text = _text(raw);
    if (text.isEmpty) return;
    fields[label] = text;
  }

  static String _bullets(Map<String, String> fields) => fields.entries
      .map((entry) => '- **${entry.key}**：${entry.value}')
      .join('\n');

  static Map<String, dynamic> _worldviewModules(Map<String, Object?> data) {
    var detail = data[SettingCardMarkdownParser.detailJsonKey];
    if (detail is String) detail = _decodeJsonMap(detail);
    if (detail is Map) {
      final modules = detail['modules'];
      if (modules is Map) return _stringKeyed(modules);
    }
    final direct = data['modules'];
    if (direct is Map) return _stringKeyed(direct);
    return <String, dynamic>{};
  }

  static String _moduleText(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString();
    if (value is List) {
      return value
          .map(_listItemText)
          .where((item) => item.isNotEmpty)
          .map((item) => '- $item')
          .join('\n');
    }
    if (value is Map) {
      final parts = <String>[];
      final bodies = <String>[];
      for (final key in _descriptionKeys) {
        final text = _text(value[key]);
        if (text.isNotEmpty && !bodies.contains(text)) bodies.add(text);
      }
      final bodyText = bodies.join('\n\n');
      if (bodyText.isNotEmpty) parts.add(bodyText);
      final items = value['items'];
      if (items is List && items.isNotEmpty) {
        // A module may carry both a formatted body and the structured entries it
        // was built from. Rendering both repeats every location/faction, so an
        // entry already represented in the body is skipped.
        final normalizedBody = bodyText.isEmpty ? '' : _squashText(bodyText);
        final lines = <String>[];
        for (final item in items) {
          final text = _listItemText(item);
          if (text.isEmpty) continue;
          if (normalizedBody.isNotEmpty) {
            final name = _squashText(_listItemName(item));
            final detail = _squashText(_listItemDescription(item));
            final normalized = _squashText(text);
            // Skip an entry only when the body already carries both its name
            // and its description. A passing mention of the name must not
            // suppress a more detailed entry the body never covered.
            if (normalizedBody.contains(normalized)) continue;
            if (name.isNotEmpty &&
                normalizedBody.contains(name) &&
                (detail.isEmpty || normalizedBody.contains(detail))) {
              continue;
            }
          }
          lines.add('- $text');
        }
        if (lines.isNotEmpty) parts.add(lines.join('\n'));
      } else if (items is String && items.trim().isNotEmpty) {
        parts.add(items.trim());
      }
      if (parts.isEmpty) {
        final extra = <String>[];
        for (final entry in value.entries) {
          final key = entry.key.toString();
          if (key == 'status' || key == 'items') continue;
          final inline = _inlineValue(entry.value);
          if (inline.isNotEmpty) extra.add('- **$key**：$inline');
        }
        if (extra.isNotEmpty) parts.add(extra.join('\n'));
      }
      return parts.join('\n\n');
    }
    return '';
  }

  static String _listItemText(Object? item) {
    if (item is String) return item.trim();
    if (item is num || item is bool) return item.toString();
    if (item is Map) {
      final name = _firstText(item, _nameKeys);
      final description = _firstText(item, _descriptionKeys);
      if (name.isNotEmpty && description.isNotEmpty) {
        return '**$name**：$description';
      }
      if (name.isNotEmpty) return '**$name**';
      if (description.isNotEmpty) return description;
      final parts = <String>[];
      for (final entry in item.entries) {
        if (entry.key.toString() == 'status') continue;
        final inline = _inlineValue(entry.value);
        if (inline.isNotEmpty) parts.add('${entry.key}：$inline');
      }
      return parts.join('；');
    }
    return '';
  }

  /// Name of a structured module entry, or empty when the entry has none.
  static String _listItemName(Object? item) {
    if (item is Map) return _firstText(item, _nameKeys);
    return '';
  }

  /// Description of a structured module entry, or empty when it has none.
  static String _listItemDescription(Object? item) {
    if (item is Map) return _firstText(item, _descriptionKeys);
    return '';
  }

  /// Whitespace- and emphasis-free form used for duplicate detection.
  static String _squashText(String value) =>
      value.replaceAll('**', '').replaceAll(RegExp(r'\s+'), '');

  static String _inlineValue(Object? value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString();
    if (value is List) {
      return value.map(_inlineValue).where((item) => item.isNotEmpty).join('、');
    }
    if (value is Map) {
      final text = _firstText(value, _descriptionKeys);
      if (text.isNotEmpty) return text;
      return value.entries
          .where((entry) => entry.key.toString() != 'status')
          .map((entry) => _inlineValue(entry.value))
          .where((item) => item.isNotEmpty)
          .join('、');
    }
    return '';
  }

  static Map<String, String> _worldProfileFields(Object? raw) {
    var value = raw;
    if (value is String) value = _decodeJsonMap(value);
    if (value is! Map) return <String, String>{};
    const labels = <String, String>{
      'faction': '所属势力',
      'home_location': '常驻地点',
      'public_goal': '公开目标',
      'hidden_motivation': '隐秘动机',
      'ability_source': '能力来源',
      'ability_cost': '能力代价',
      'taboos': '禁忌',
      'relationship_notes': '关系备注',
      'secrets': '秘密',
    };
    final fields = <String, String>{};
    for (final entry in labels.entries) {
      final text = _inlineValue(value[entry.key]);
      if (text.isNotEmpty) fields[entry.value] = text;
    }
    return fields;
  }

  static String _customAttributeLines(Object? raw) {
    var value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return '';
      }
    }
    if (value is! List) return '';
    final lines = <String>[];
    for (final item in value) {
      if (item is String) {
        if (item.trim().isNotEmpty) lines.add('- ${item.trim()}');
        continue;
      }
      if (item is! Map) continue;
      final name = _firstText(item, _nameKeys);
      final detail = _inlineValue(item['value'] ?? item['content']);
      if (name.isNotEmpty && detail.isNotEmpty) {
        lines.add('- **$name**：$detail');
      } else if (name.isNotEmpty) {
        lines.add('- **$name**');
      } else if (detail.isNotEmpty) {
        lines.add('- $detail');
      }
    }
    return lines.join('\n');
  }

  static String _firstText(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final text = _text(map[key]);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _text(Object? value) {
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString();
    return '';
  }

  static Map<String, dynamic> _stringKeyed(Map<dynamic, dynamic> map) =>
      <String, dynamic>{
        for (final entry in map.entries) entry.key.toString(): entry.value,
      };

  static Map<String, dynamic>? _decodeJsonMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return _stringKeyed(decoded);
    } on FormatException {
      return null;
    }
    return null;
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

  /// Renders a legacy card JSON payload as a readable document body.
  ///
  /// The mirror body follows the same single-document shape as a generated
  /// card: readable Chinese sections, never a raw JSON object. A payload that
  /// cannot be decoded is kept verbatim as plain text so nothing is lost.
  static String cardContent(String jsonData) {
    final trimmed = jsonData.trim();
    if (trimmed.isEmpty) return '';
    final decoded = _tryDecodeJson(trimmed);
    if (decoded is Map) {
      final data = decoded['data'];
      final card = data is Map
          ? <String, Object?>{
              for (final entry in data.entries)
                entry.key.toString(): entry.value,
            }
          : <String, Object?>{
              for (final entry in decoded.entries)
                entry.key.toString(): entry.value,
            };
      final rendered = SettingCardDocumentRenderer.renderCharacter(card);
      if (rendered.trim().isNotEmpty) return rendered;
      // The payload decoded but carried nothing renderable. Returning the raw
      // JSON would put an object back into the editor, so only readable prose
      // survives.
      return _firstReadableText(card);
    }
    return trimmed;
  }

  /// First readable prose value of a decoded card payload, else empty.
  static String _firstReadableText(Map<dynamic, dynamic> card) {
    for (final key in const <String>[
      'description',
      'background',
      'personality',
      'name',
    ]) {
      final value = card[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
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

  /// Renders a worldview description and its detail modules as readable text.
  ///
  /// The description acts as the overview fallback; detail modules are expanded
  /// with the standard Chinese section titles instead of being fenced as JSON.
  static String worldviewContent({
    required String description,
    String detailJson = '',
  }) {
    final text = description.trim();
    final data = <String, Object?>{'description': text};
    final detail = detailJson.trim();
    if (detail.isNotEmpty) {
      final decoded = _tryDecodeJson(detail);
      if (decoded is Map) {
        final modules = decoded['modules'];
        if (modules is Map) {
          final normalized = <String, Object?>{
            for (final entry in modules.entries)
              entry.key.toString(): entry.value,
          };
          // A legacy save authors the description explicitly and stores the
          // structured detail next to it. That description is the readable
          // overview, so it must win over the module copy instead of being
          // dropped as a duplicate fallback.
          if (text.isNotEmpty) normalized['overview'] = text;
          data['modules'] = normalized;
        } else {
          data['detail_json'] = decoded;
        }
      }
    }
    return SettingCardDocumentRenderer.renderWorldview(data);
  }

  static Object? _tryDecodeJson(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      return null;
    }
  }
}
