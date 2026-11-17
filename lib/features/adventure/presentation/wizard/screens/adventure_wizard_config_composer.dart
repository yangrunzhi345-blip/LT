part of 'adventure_wizard_screen.dart';

extension _WizardConfigComposer on _AdventureWizardScreenState {
  String _getOrCreateActiveWorldviewId() {
    if (_selectedWorldviewId != null && _selectedWorldviewId!.isNotEmpty) {
      return _selectedWorldviewId!;
    }
    final newId = 'wv_wizard_${DateTime.now().millisecondsSinceEpoch}';
    _selectedWorldviewId = newId;
    return newId;
  }

  /// 获取当前向导中活跃的世界观设定项（包含用户填写的名称与法则描述）
  Map<String, dynamic> _getActiveWorldviewItem() {
    final id = _getOrCreateActiveWorldviewId();
    final name = _worldviewNameCtrl.text.trim().isNotEmpty
        ? _worldviewNameCtrl.text.trim()
        : '当前世界观';
    final desc = _worldviewDescCtrl.text.trim();
    final existing =
        _worldviews.where((w) => w['id']?.toString() == id).firstOrNull;
    if (existing != null) {
      return {
        ...existing,
        'name': name,
        'description': desc,
      };
    }
    return {
      'id': id,
      'name': name,
      'description': desc,
      'detail_json': '{}',
    };
  }

  /// 构造包含当前活跃世界观的高优先级世界观列表，确保角色设计与 AI 创作第一时间自动关联
  List<Map<String, dynamic>> _buildEffectiveWorldviews() {
    final activeItem = _getActiveWorldviewItem();
    final list = <Map<String, dynamic>>[activeItem];
    for (final w in _worldviews) {
      if (w['id']?.toString() != activeItem['id']?.toString()) {
        list.add(w);
      }
    }
    return list;
  }

  /// 手动或自动将当前编辑的世界观设定保存至资料库
  WizardCharacterItem get _protagonistItem {
    final protagonist = _characters.where((c) => c.isProtagonist).firstOrNull;
    if (protagonist != null) return protagonist;
    if (_characters.isNotEmpty) return _characters.first;
    return WizardCharacterItem(
        id: 'protagonist', name: _l10n(context).explorerRole);
  }

  List<AdventureSelectedCharacter> _composeSelectedCharacters() {
    final result = <AdventureSelectedCharacter>[];
    for (var i = 0; i < _characters.length; i++) {
      final c = _characters[i];
      final cardJson = Map<String, dynamic>.from(c.rawJson ??
          {
            'name': c.name,
            'gender': c.gender,
            'age': c.age,
            'profession': c.profession,
            'personality': c.personality,
            'description': c.background,
          });
      if ((c.libraryEntry?.customAttributes.isNotEmpty ?? false) &&
          cardJson['custom_attributes'] == null &&
          cardJson['customAttributes'] == null) {
        cardJson['custom_attributes'] =
            c.libraryEntry!.customAttributes.map((a) => a.toJson()).toList();
      }
      result.add(AdventureSelectedCharacter(
        id: c.id,
        characterId: c.id,
        characterName: c.name,
        isProtagonist: c.isProtagonist,
        narrativeRole: c.narrativeRole,
        customRoleName: c.customRoleName,
        sortOrder: c.isProtagonist ? 0 : i + 1,
        characterCardJson: cardJson,
      ));
    }
    return result;
  }

  List<AdventureCharacterRelationship> _composeRelationships() => _relationships
      .map((r) => AdventureCharacterRelationship(
            id: r.id,
            sourceCharacterId: r.sourceCharacterId,
            targetCharacterId: r.targetCharacterId,
            relationType: r.relationType,
            customRelationName: r.customRelationName,
            sourceRole: r.sourceRole,
            targetRole: r.targetRole,
            description: r.description,
          ))
      .toList();

  List<SupportingCharacter> _composeSupportingCharacters(
      WizardCharacterItem protagonist) {
    final result = <SupportingCharacter>[];
    for (final c in _characters) {
      if (c.isProtagonist) continue;
      final rel = _relationships
          .where((r) =>
              (r.sourceCharacterId == protagonist.id &&
                  r.targetCharacterId == c.id) ||
              (r.sourceCharacterId == c.id &&
                  r.targetCharacterId == protagonist.id))
          .firstOrNull;

      final rawAttrs = c.libraryEntry?.customAttributes;
      final listAttrs = (rawAttrs != null && rawAttrs.isNotEmpty)
          ? rawAttrs
          : (c.rawJson != null &&
                  (c.rawJson!['custom_attributes'] is List ||
                      c.rawJson!['customAttributes'] is List))
              ? ((c.rawJson!['custom_attributes'] ??
                      c.rawJson!['customAttributes']) as List)
                  .map((item) => CustomAttributeItem.fromJson(
                      Map<String, dynamic>.from(item as Map)))
                  .toList()
              : <CustomAttributeItem>[];

      result.add(
        SupportingCharacter(
          id: c.id,
          name: c.name,
          gender: c.gender,
          role: c.profession.isNotEmpty ? c.profession : c.effectiveRole,
          relation: rel != null &&
                  AdventureRelationType.normalize(rel.relationType) !=
                      AdventureRelationType.unset
              ? rel.effectiveRelation
              : '',
          personality: c.personality,
          customAttributes: listAttrs,
        ),
      );
    }
    return result;
  }

  Map<String, dynamic> _npcJsonOf(Map<String, dynamic> row) {
    try {
      final decoded = jsonDecode(row['json_data']?.toString() ?? '{}');
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  Iterable<Map<String, dynamic>> get _selectedNpcRows =>
      _npcCards.where((npc) => _selectedNpcIds.contains(npc['id']?.toString()));

  List<AdventureNpcSnapshot> _composeNpcSnapshots() => _selectedNpcRows
      .map((row) => AdventureNpcSnapshot(
            assetId: row['id']?.toString() ?? '',
            name: row['name']?.toString().trim().isNotEmpty == true
                ? row['name'].toString().trim()
                : _l10n(context).unnamedNpc,
            originWorldviewId: row['matching_worldview_id']?.toString() ?? '',
            npcJson: _npcJsonOf(row),
          ))
      .toList();

  List<SupportingCharacter> _supportingWithNpcs(
      List<SupportingCharacter> supporting) {
    final result = List<SupportingCharacter>.from(supporting);
    for (final row in _selectedNpcRows) {
      final assetId = row['id']?.toString() ?? '';
      final name = row['name']?.toString().trim().isNotEmpty == true
          ? row['name'].toString().trim()
          : _l10n(context).unnamedNpc;
      final npcJson = _npcJsonOf(row);
      result.add(SupportingCharacter.fromJson({
        ...npcJson,
        'id': assetId,
        'name': name,
        'relation': npcJson['relation']?.toString() ?? '',
      }));
    }
    return result;
  }

  AdventureConfig _composeAdventureConfig({
    required String worldview,
    Map<String, dynamic>? worldviewSnapshot,
  }) {
    final protagonist = _protagonistItem;
    final openingOpts = [
      _option1Ctrl.text.trim(),
      _option2Ctrl.text.trim(),
      _option3Ctrl.text.trim(),
    ].where((opt) => opt.isNotEmpty).toList();
    return AdventureConfig(
      worldview: worldview,
      worldviewSnapshot: worldviewSnapshot,
      name: protagonist.name,
      gender: protagonist.gender,
      age: protagonist.age,
      protagonistClass: protagonist.profession.isNotEmpty
          ? protagonist.profession
          : _l10n(context).explorerRole,
      personality: protagonist.personality,
      protagonistBackground: protagonist.background,
      characterCard: protagonist.libraryEntry?.card ??
          CharacterCard.fromJson(protagonist.rawJson ??
              {
                'name': protagonist.name,
                'gender': protagonist.gender,
                'age': protagonist.age,
                'profession': protagonist.profession,
                'personality': protagonist.personality,
                'description': protagonist.background,
              }),
      selectedCharacters: _composeSelectedCharacters(),
      characterRelationships: _composeRelationships(),
      supportingCharacters:
          _supportingWithNpcs(_composeSupportingCharacters(protagonist)),
      npcSnapshots: _composeNpcSnapshots(),
      openingScene: _openingSceneCtrl.text.trim().isNotEmpty
          ? _openingSceneCtrl.text.trim()
          : _l10n(context).adventureDefaultOpeningScene,
      openingOptions: openingOpts.isNotEmpty
          ? openingOpts
          : [
              _l10n(context).adventureDefaultOpeningOptionOne,
              _l10n(context).adventureDefaultOpeningOptionTwo,
              _l10n(context).adventureDefaultOpeningOptionThree,
            ],
    );
  }

  /// Saves the current wizard state as a recoverable preview template without
  /// starting the adventure.
}
