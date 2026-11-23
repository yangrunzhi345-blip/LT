import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_markdown_parser.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_reference_input.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/generation_stage_progress.dart';
import 'package:lt_dialogue/models/generation_task_handle.dart';

import '../../helpers/setting_card_fakes.dart';

void main() {
  late MemorySettingCardRepository repository;
  late FakeSettingCardGateway gateway;
  late SettingCardService service;

  setUp(() {
    repository = MemorySettingCardRepository();
    gateway = FakeSettingCardGateway();
    var sequence = 0;
    service = SettingCardService(
      repository: repository,
      gateway: gateway,
      clock: () => '2026-07-01T00:00:00.000',
      idGenerator: () {
        sequence++;
        return 'card-$sequence';
      },
    );
  });

  test('create stores one document with the supplied mode', () async {
    final card = await service.create(
      kind: SettingCardKind.worldview,
      name: '银月大陆',
      summary: '概述',
      mode: 'adventure',
    );

    expect(card.id, 'card-1');
    expect(card.mode, 'adventure');
    expect(repository.cards['card-1'], isNotNull);
  });

  test('list filters by library mode but keeps unclassified cards', () async {
    await service.create(
      kind: SettingCardKind.character,
      name: '冒险角色',
      mode: 'adventure',
    );
    await service.create(
      kind: SettingCardKind.character,
      name: '对话角色',
      mode: 'conversation',
    );
    await service.create(
      kind: SettingCardKind.character,
      name: '未分类',
    );

    final adventure = await service.list(mode: 'adventure');

    expect(adventure.map((card) => card.name).toSet(), <String>{'冒险角色', '未分类'});
  });

  test('save updates name, summary and body together', () async {
    await service.create(kind: SettingCardKind.npc, name: '守卫');
    final saved = await service.save(
      id: 'card-1',
      name: '北门守卫',
      summary: '守序',
      content: '# 北门守卫\n\n忠于银月城。',
    );

    expect(saved.name, '北门守卫');
    expect(saved.content, contains('忠于银月城'));
    expect(saved.updatedAt, '2026-07-01T00:00:00.000');
  });

  test('delete hides the card but keeps the row restorable', () async {
    await service.create(kind: SettingCardKind.character, name: '林恩');

    await service.delete('card-1');

    expect(await service.list(), isEmpty);
    final all = await repository.list(includeDeleted: true);
    expect(all.single.isDeleted, isTrue);
  });

  test('generate makes exactly one request and merges the document', () async {
    gateway.worldviewResponse = <String, dynamic>{
      'name': '银月大陆',
      'description': '被月光笼罩的大陆',
      'modules': <String, dynamic>{
        'history': '三百年前的战争',
      },
    };
    await service.create(kind: SettingCardKind.worldview, name: '');

    final stages = <GenerationStageProgress>[];
    final card = await service.generate(
      id: 'card-1',
      instruction: '生成一个奇幻大陆',
      onProgress: stages.add,
    );

    expect(gateway.worldviewCalls, 1);
    expect(gateway.sources.single, '生成一个奇幻大陆');
    expect(stages, isNotEmpty);
    expect(stages.first.stageName, '概览');
    expect(stages.first.currentCharacters, 120);
    expect(stages.first.targetCharacters, 2000);
    expect(card.name, '银月大陆');
    expect(card.summary, '被月光笼罩的大陆');
    // The document is human-readable Markdown, never a JSON fence or a raw
    // module object leaked into the editor.
    expect(card.content, contains('## 概览'));
    expect(card.content, contains('被月光笼罩的大陆'));
    expect(card.content, contains('三百年前的战争'));
    expect(card.content, isNot(contains('```json')));
    expect(card.content, isNot(contains('## detail_json')));
    expect(card.content, isNot(contains('"modules"')));
    expect(card.content.trimLeft().startsWith('{'), isFalse);
  });

  test('generate without an instruction expands the current body', () async {
    gateway.characterResponse = <String, dynamic>{
      'name': '林恩',
      'description': '游侠',
    };
    await service.create(kind: SettingCardKind.character, name: '林恩');
    await service.save(
      id: 'card-1',
      name: '林恩',
      summary: '',
      content: '现有的角色草稿',
    );

    await service.generate(id: 'card-1', instruction: '  ');

    expect(gateway.sources.single, '现有的角色草稿');
    expect(gateway.characterCalls, 1);
  });

  test('generate fails closed when AI is not configured', () async {
    gateway.configured = false;
    await service.create(kind: SettingCardKind.worldview, name: 'x');

    expect(
      () => service.generate(id: 'card-1', instruction: 'y'),
      throwsA(isA<SettingCardGenerationException>()),
    );
    expect(gateway.worldviewCalls, 0);
  });

  test('generate wraps upstream failures without leaking the payload',
      () async {
    gateway.error = StateError('network down');
    await service.create(kind: SettingCardKind.worldview, name: 'x');

    await expectLater(
      service.generate(id: 'card-1', instruction: 'y'),
      throwsA(isA<SettingCardGenerationException>()),
    );
    final stored = repository.cards['card-1']!;
    expect(stored.content, isEmpty);
  });

  group('generate input plumbing', () {
    test('forwards worldview, associated characters and target size', () async {
      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'personality': '冷静',
      };
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '冒险角色',
      );
      final longPersonality = '性' * 300;
      final longBackground = '背' * 500;

      await service.generate(
        id: card.id,
        instruction: '生成一个角色',
        worldview: 'W',
        associatedCharacters: <Map<String, String>>[
          <String, String>{
            'name': '甲',
            'profession': '剑士',
            'personality': longPersonality,
            'background': longBackground,
            'relation': '同伴',
          },
        ],
        targetTotalCharacters: 9000,
      );

      expect(gateway.worldviews.last, 'W');
      final summarized = gateway.associatedCharacterArgs.last.single;
      expect(summarized['name'], '甲');
      expect(summarized['relation'], '同伴');
      expect(summarized['personality']!.length, 280);
      expect(summarized['background']!.length, 400);
      expect(gateway.targetCharacterArgs.last, 9000);
    });

    test('loads the origin worldview card when none is passed', () async {
      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'personality': '冷静',
      };
      final worldview = await service.create(
        kind: SettingCardKind.worldview,
        name: '银月大陆',
        content: 'WORLD-BODY',
      );
      final character = await service.create(
        kind: SettingCardKind.character,
        name: '林恩',
        originWorldviewId: worldview.id,
      );

      await service.generate(id: character.id, instruction: '生成角色');

      expect(gateway.worldviews.last, contains('WORLD-BODY'));
    });

    test('an explicit worldview wins over the origin card', () async {
      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'personality': '冷静',
      };
      final worldview = await service.create(
        kind: SettingCardKind.worldview,
        name: '银月大陆',
        content: 'WORLD-BODY',
      );
      final character = await service.create(
        kind: SettingCardKind.character,
        name: '林恩',
        originWorldviewId: worldview.id,
      );

      await service.generate(
        id: character.id,
        instruction: '生成角色',
        worldview: 'EXPLICIT',
      );

      expect(gateway.worldviews.last, contains('EXPLICIT'));
      expect(gateway.worldviews.last, isNot(contains('WORLD-BODY')));
    });
  });

  group('generated metadata', () {
    test('character generation stores the structured payload', () async {
      gateway.characterResponse = <String, dynamic>{
        'name': 'A',
        'personality': 'P',
      };
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '冒险角色',
      );

      final generated = await service.generate(id: card.id, instruction: '生成');

      final payload =
          generated.metadata[SettingCardMarkdownParser.structuredPayloadKey];
      expect(payload, isA<Map>());
      expect((payload! as Map)['personality'], 'P');
    });

    test('worldview generation stores the detail json map', () async {
      gateway.worldviewResponse = <String, dynamic>{
        'detail_json': <String, dynamic>{
          'modules': <String, dynamic>{
            'overview': <String, dynamic>{'summary': '大陆概览'},
          },
        },
      };
      final card = await service.create(
        kind: SettingCardKind.worldview,
        name: '银月大陆',
      );

      final generated = await service.generate(id: card.id, instruction: '生成');

      final detail =
          generated.metadata[SettingCardMarkdownParser.detailJsonKey];
      expect(detail, isA<Map>());
      final modules = (detail! as Map)['modules'];
      expect(modules, isA<Map>());
      expect((modules! as Map)['overview'], isA<Map>());
    });
  });

  group('reference material', () {
    test('a missing existing-card reference fails with its id', () async {
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '冒险角色',
      );

      await expectLater(
        service.generate(
          id: card.id,
          instruction: '生成',
          reference: const SettingCardReferenceInput(
            mode: SettingCardReferenceMode.existingCard,
            sourceCardId: 'missing',
          ),
        ),
        throwsA(
          isA<SettingCardGenerationException>().having(
            (error) => error.message,
            'message',
            contains('missing'),
          ),
        ),
      );
      expect(gateway.characterCalls, 0);
    });

    test('an existing-card reference injects the referenced body', () async {
      gateway.characterResponse = <String, dynamic>{
        'name': '新角色',
        'personality': '谨慎',
      };
      final reference = await service.create(
        kind: SettingCardKind.character,
        name: '旧角色',
        content: 'REFERENCE-BODY',
      );
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '新角色',
      );

      await service.generate(
        id: card.id,
        instruction: '生成',
        reference: SettingCardReferenceInput(
          mode: SettingCardReferenceMode.existingCard,
          sourceCardId: reference.id,
        ),
      );

      expect(gateway.sources.last, contains('REFERENCE-BODY'));
    });
  });

  test('a plain-text card without metadata still regenerates', () async {
    final card = await service.create(
      kind: SettingCardKind.character,
      name: '旧卡',
      content: '纯文本正文，不是 JSON',
    );
    gateway.characterResponse = <String, dynamic>{
      'name': '新名',
      'description': '新正文',
    };

    final generated = await service.generate(id: card.id, instruction: '重写');

    expect(generated.content, contains('新正文'));
    expect(generated.content, isNot(contains('纯文本正文')));
    expect(
      generated.metadata[SettingCardMarkdownParser.structuredPayloadKey],
      isA<Map>(),
    );
  });

  test('origin worldview is normalized into modules before budgeting',
      () async {
    final worldview = await service.create(
      kind: SettingCardKind.worldview,
      name: '银月大陆',
      content: '''
## 概览

月光大陆。

## 地点与地理

### 银月城

月光之城。
''',
    );
    final character = await service.create(
      kind: SettingCardKind.character,
      name: '林恩',
      originWorldviewId: worldview.id,
    );
    gateway.characterResponse = <String, dynamic>{
      'name': '林恩',
      'personality': '冷静',
    };

    await service.generate(id: character.id, instruction: '生成角色');

    final injected = gateway.worldviews.last;
    expect(injected, contains('【locations】'));
    expect(injected, contains('银月城'));
    expect(injected, contains('【overview】'));
  });

  group('previous content snapshot', () {
    test('generate keeps exactly the body it overwrites', () async {
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '林恩',
        summary: '旧摘要',
        content: '第一版正文',
      );
      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'description': '第二版正文',
      };

      final first = await service.generate(id: card.id, instruction: '重写');

      final snapshot =
          first.metadata[SettingCardService.previousSnapshotKey] as Map;
      expect(snapshot['content'], '第一版正文');
      expect(snapshot['summary'], '旧摘要');
      expect(snapshot['saved_at'], '2026-07-01T00:00:00.000');
      expect(
        snapshot.keys.toSet(),
        <String>{'content', 'summary', 'saved_at'},
      );
      expect(first.content, contains('第二版正文'));

      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'description': '第三版正文',
      };
      final second = await service.generate(id: card.id, instruction: '再写');

      final replaced =
          second.metadata[SettingCardService.previousSnapshotKey] as Map;
      expect(replaced['content'], contains('第二版正文'));
      expect(replaced['content'], isNot(contains('第一版正文')));
    });

    test('restorePreviousSnapshot puts the old body and payload back once',
        () async {
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '林恩',
        summary: '旧摘要',
        content: '旧正文',
      );
      await repository.save(card.copyWith(
        metadata: <String, Object?>{
          SettingCardMarkdownParser.structuredPayloadKey: <String, Object?>{
            'personality': '旧性格',
          },
        },
      ));
      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'personality': '新性格',
      };

      final generated = await service.generate(id: card.id, instruction: '重写');
      expect(generated.content, isNot(contains('旧正文')));

      final restored = await service.restorePreviousSnapshot(card.id);

      expect(restored, isNotNull);
      expect(restored!.content, '旧正文');
      expect(restored.summary, '旧摘要');
      final payload = restored
          .metadata[SettingCardMarkdownParser.structuredPayloadKey] as Map;
      expect(payload['personality'], '旧性格');
      expect(
        restored.metadata.containsKey(SettingCardService.previousSnapshotKey),
        isFalse,
      );

      expect(await service.restorePreviousSnapshot(card.id), isNull);
      final stored = (await repository.findById(card.id))!;
      expect(stored.content, '旧正文');
    });

    test('restoring drops payload keys the snapshot never had', () async {
      final card = await service.create(
        kind: SettingCardKind.worldview,
        name: '银月大陆',
        content: '旧世界观正文',
      );
      gateway.worldviewResponse = <String, dynamic>{
        'detail_json': <String, dynamic>{
          'modules': <String, dynamic>{'overview': '新概览'},
        },
      };

      final generated = await service.generate(id: card.id, instruction: '重写');
      expect(
        generated.metadata.containsKey(SettingCardMarkdownParser.detailJsonKey),
        isTrue,
      );

      final restored = (await service.restorePreviousSnapshot(card.id))!;

      expect(restored.content, '旧世界观正文');
      expect(
        restored.metadata.containsKey(SettingCardMarkdownParser.detailJsonKey),
        isFalse,
      );
    });

    test('worldview detail json travels with the snapshot', () async {
      final card = await service.create(
        kind: SettingCardKind.worldview,
        name: '银月大陆',
        content: '第一版世界观',
      );
      gateway.worldviewResponse = <String, dynamic>{
        'detail_json': <String, dynamic>{
          'modules': <String, dynamic>{
            'overview': <String, dynamic>{'summary': '第二版概览'},
          },
        },
      };
      await service.generate(id: card.id, instruction: '重写');

      gateway.worldviewResponse = <String, dynamic>{
        'detail_json': <String, dynamic>{
          'modules': <String, dynamic>{
            'overview': <String, dynamic>{'summary': '第三版概览'},
          },
        },
      };
      final second = await service.generate(id: card.id, instruction: '再写');

      final snapshot =
          second.metadata[SettingCardService.previousSnapshotKey] as Map;
      final snapshotModules =
          (snapshot['detail_json'] as Map)['modules'] as Map;
      expect(
        (snapshotModules['overview'] as Map)['summary'],
        '第二版概览',
      );

      final restored = (await service.restorePreviousSnapshot(card.id))!;
      final detail =
          restored.metadata[SettingCardMarkdownParser.detailJsonKey] as Map;
      final modules = detail['modules'] as Map;
      expect((modules['overview'] as Map)['summary'], '第二版概览');
      expect(restored.content, contains('第二版概览'));
    });

    test('generate does not snapshot an empty body', () async {
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '林恩',
      );
      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'personality': '冷静',
      };

      final generated = await service.generate(id: card.id, instruction: '生成');

      expect(generated.content, isNotEmpty);
      expect(
        generated.metadata.containsKey(SettingCardService.previousSnapshotKey),
        isFalse,
      );
    });

    test('a failed generation writes no snapshot', () async {
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '林恩',
        content: '需要保留的正文',
      );
      gateway.error = StateError('network down');

      await expectLater(
        service.generate(id: card.id, instruction: '重写'),
        throwsA(isA<SettingCardGenerationException>()),
      );

      final stored = (await repository.findById(card.id))!;
      expect(stored.content, '需要保留的正文');
      expect(
        stored.metadata.containsKey(SettingCardService.previousSnapshotKey),
        isFalse,
      );
    });
  });

  group('discardEmptyDraft', () {
    test('soft deletes an empty draft only', () async {
      final empty = await service.create(
        kind: SettingCardKind.character,
        name: '空卡',
      );
      final filled = await service.create(
        kind: SettingCardKind.character,
        name: '有内容',
        content: '正文',
      );

      await service.discardEmptyDraft(empty.id);

      expect(repository.cards[empty.id]!.isDeleted, isTrue);
      expect(repository.cards[filled.id]!.isDeleted, isFalse);
      expect(repository.cards[filled.id]!.content, '正文');
    });

    test('a whitespace-only body counts as empty', () async {
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '空白',
        content: '  \n ',
      );

      await service.discardEmptyDraft(card.id);

      expect(repository.cards[card.id]!.isDeleted, isTrue);
    });

    test('a missing id is a no-op', () async {
      await service.discardEmptyDraft('missing');

      expect(repository.cards, isEmpty);
    });
  });

  test('regeneration keeps the card tracking definitions', () async {
    const definitions = <Map<String, Object?>>[
      <String, Object?>{'id': 'mood', 'name': '心情'},
    ];
    final card = await service.create(
      kind: SettingCardKind.character,
      name: '林恩',
      content: '旧正文',
    );
    await repository.save(card.copyWith(
      metadata: <String, Object?>{
        SettingCardMarkdownParser.structuredPayloadKey: <String, Object?>{
          'personality': '旧性格',
          'tracked_state_definitions': definitions,
        },
      },
    ));
    gateway.characterResponse = <String, dynamic>{
      'name': '林恩',
      'personality': '新性格',
    };

    final generated = await service.generate(
      id: card.id,
      instruction: '重写性格',
    );

    final payload = generated
        .metadata[SettingCardMarkdownParser.structuredPayloadKey] as Map;
    expect(payload['personality'], '新性格');
    expect(payload['tracked_state_definitions'], definitions);
  });

  test('worldview regeneration keeps detail_json definitions', () async {
    const definitions = <Map<String, Object?>>[
      <String, Object?>{'id': 'war', 'name': '战争紧张度'},
    ];
    final card = await service.create(
      kind: SettingCardKind.worldview,
      name: '银月大陆',
      content: '旧正文',
    );
    await repository.save(card.copyWith(
      metadata: <String, Object?>{
        SettingCardMarkdownParser.detailJsonKey: <String, Object?>{
          'modules': <String, Object?>{
            'overview': <String, Object?>{'summary': '旧'},
          },
          'tracked_state_definitions': definitions,
        },
      },
    ));
    gateway.worldviewResponse = <String, dynamic>{
      'name': '银月大陆',
      'description': '新概述',
      'detail_json': <String, Object?>{
        'modules': <String, Object?>{
          'overview': <String, Object?>{'summary': '新'},
        },
      },
    };

    final generated = await service.generate(id: card.id, instruction: '重写');

    final detail =
        generated.metadata[SettingCardMarkdownParser.detailJsonKey] as Map;
    expect((detail['modules'] as Map)['overview'], isA<Map>());
    expect(detail['tracked_state_definitions'], definitions);
  });

  group('rendered documents', () {
    test('worldview modules render as readable Chinese sections', () async {
      gateway.worldviewResponse = <String, dynamic>{
        'name': '银月大陆',
        'description': '被月光笼罩的大陆',
        'detail_json': <String, dynamic>{
          'format_version': 2,
          'mode': 'detailed',
          'modules': <String, dynamic>{
            'overview': <String, dynamic>{
              'summary': '银月大陆概览',
              'status': 'confirmed',
            },
            'locations': <dynamic>[
              <String, dynamic>{'name': '银月城', 'summary': '月光之城'},
              <String, dynamic>{'name': '北门', 'description': '边境要塞'},
            ],
            'factions': <String, dynamic>{
              'content': '银月议会',
              'status': 'confirmed'
            },
            'unknown_module': <String, dynamic>{'summary': '未知模块文本'},
          },
        },
      };
      final card =
          await service.create(kind: SettingCardKind.worldview, name: '');

      final generated = await service.generate(id: card.id, instruction: '生成');

      expect(generated.content, contains('## 概览'));
      expect(generated.content, contains('银月大陆概览'));
      expect(generated.content, contains('## 地点与地理'));
      expect(generated.content, contains('- **银月城**：月光之城'));
      expect(generated.content, contains('## 势力与组织'));
      expect(generated.content, contains('银月议会'));
      expect(generated.content, contains('## unknown_module'));
      expect(generated.content, contains('未知模块文本'));
      expect(generated.content, isNot(contains('```')));
      expect(generated.content, isNot(contains('"status"')));
    });

    test('worldview module with body and items renders each entry once',
        () async {
      gateway.worldviewResponse = <String, dynamic>{
        'name': '银月大陆',
        'description': '被月光笼罩的大陆',
        'detail_json': <String, dynamic>{
          'modules': <String, dynamic>{
            'overview': <String, dynamic>{'summary': '银月大陆概览'},
            'locations': <String, dynamic>{
              'content': '银月城是月光之城，北门是边境要塞。',
              'items': <dynamic>[
                <String, dynamic>{'name': '银月城', 'description': '月光之城'},
                <String, dynamic>{'name': '北门', 'description': '边境要塞'},
              ],
            },
          },
        },
      };
      final card =
          await service.create(kind: SettingCardKind.worldview, name: '');

      final generated = await service.generate(id: card.id, instruction: '生成');

      // The formatted body already describes both places, so the structured
      // items must not repeat them.
      expect('银月城'.allMatches(generated.content).length, 1);
      expect('北门'.allMatches(generated.content).length, 1);
      expect(generated.content, contains('## 地点与地理'));
      expect(generated.content, isNot(contains('```')));
    });

    test('worldview detail_json may arrive as a JSON string', () async {
      gateway.worldviewResponse = <String, dynamic>{
        'name': '银月大陆',
        'description': '被月光笼罩的大陆',
        'detail_json': jsonEncode(<String, dynamic>{
          'modules': <String, dynamic>{
            'overview': <String, dynamic>{'summary': '银月大陆概览'},
            'locations': <dynamic>[
              <String, dynamic>{'name': '银月城', 'summary': '月光之城'},
            ],
          },
        }),
      };
      final card =
          await service.create(kind: SettingCardKind.worldview, name: '');

      final generated = await service.generate(id: card.id, instruction: '生成');

      expect(generated.content, contains('## 概览'));
      expect(generated.content, contains('银月大陆概览'));
      expect(generated.content, contains('## 地点与地理'));
      expect(generated.content, isNot(contains('```')));
      final detail =
          generated.metadata[SettingCardMarkdownParser.detailJsonKey];
      expect(detail, isA<Map>());
    });

    test('character payload renders fixed Chinese sections without JSON',
        () async {
      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'gender': '男',
        'age': '24',
        'profession': '游侠',
        'archetype': '流浪者',
        'personality': '沉默但可靠。',
        'appearance': '黑发灰眼。',
        'bodyDescription': '高瘦。',
        'description': '来自北境。',
        'background': '来自北境。',
        'world_profile': <String, dynamic>{
          'faction': '银月城',
          'home_location': '北门',
          'taboos': <String>['不可背誓', '不可欺凌弱者'],
        },
        'ability': '长弓',
        'weakness': '怕水',
        'equipment': '旧弓',
        'speaking_style': '简短',
        'character_arc': '从独行到守护',
        'first_mes': '走吧。',
        'mes_example': '甲：走。',
        'custom_attributes': <dynamic>[
          <String, dynamic>{'name': '魔力', 'value': '25/100'},
        ],
      };
      final card =
          await service.create(kind: SettingCardKind.character, name: '林恩');

      final generated = await service.generate(id: card.id, instruction: '生成');

      expect(generated.content, contains('## 基础信息'));
      expect(generated.content, contains('- **姓名**：林恩'));
      expect(generated.content, contains('## 性格与心理'));
      expect(generated.content, contains('## 世界定位与动机'));
      expect(
        generated.content,
        contains('- **禁忌**：不可背誓、不可欺凌弱者'),
      );
      expect(generated.content, contains('## 自定义属性'));
      expect(generated.content, contains('- **魔力**：25/100'));
      // description and background carry the same text: render it once.
      expect('来自北境'.allMatches(generated.content).length, 1);
      expect(generated.content, isNot(contains('```')));
      expect(generated.content, isNot(contains('## detail')));
      expect(generated.content.trimLeft().startsWith('{'), isFalse);
    });
  });

  group('legacy mirror bodies', () {
    test('card mirror renders a readable character document', () {
      final content = LegacyCardMirror.cardContent(
        jsonEncode(<String, dynamic>{
          'data': <String, dynamic>{
            'name': '林恩',
            'gender': '男',
            'personality': '沉默但可靠。',
            'appearance': '黑发灰眼。',
          },
        }),
      );

      expect(content, contains('## 基础信息'));
      expect(content, contains('- **姓名**：林恩'));
      expect(content, contains('## 性格与心理'));
      expect(content, isNot(contains('```')));
      expect(content, isNot(contains('"personality"')));
      expect(content.trimLeft().startsWith('{'), isFalse);
    });

    test('worldview mirror expands detail modules instead of fenced JSON', () {
      final content = LegacyCardMirror.worldviewContent(
        description: '被月光笼罩的大陆',
        detailJson: jsonEncode(<String, dynamic>{
          'modules': <String, dynamic>{
            'overview': <String, dynamic>{'summary': '大陆概览'},
            'locations': <dynamic>[
              <String, dynamic>{'name': '银月城', 'summary': '月光之城'},
            ],
          },
        }),
      );

      expect(content, contains('## 概览'));
      expect(content, contains('## 地点与地理'));
      expect(content, contains('- **银月城**：月光之城'));
      expect(content, isNot(contains('```')));
      expect(content, isNot(contains('## detail')));
    });

    test('worldview mirror keeps the authored description as overview', () {
      final content = LegacyCardMirror.worldviewContent(
        description: '玩家写下的世界描述。',
        detailJson: jsonEncode(<String, dynamic>{
          'modules': <String, dynamic>{
            'overview': <String, dynamic>{'summary': '模型概览'},
            'locations': <dynamic>[
              <String, dynamic>{'name': '银月城', 'summary': '月光之城'},
            ],
          },
        }),
      );

      expect(content, contains('玩家写下的世界描述。'));
      expect(content, contains('## 地点与地理'));
      expect(content, contains('银月城'));
    });

    test('card mirror never returns a raw JSON object', () {
      final content =
          LegacyCardMirror.cardContent('{"spec":"x","spec_version":2}');

      expect(content, isEmpty);
      expect(content, isNot(contains('{')));
    });

    test('an unparseable legacy body stays plain text without a fence', () {
      final content = LegacyCardMirror.cardContent('not json at all');

      expect(content, 'not json at all');
    });
  });

  group('generation plumbing', () {
    test('NPC generation forwards isNpc and the task handle', () async {
      gateway.characterResponse = <String, dynamic>{
        'name': '守卫',
        'personality': '忠诚',
      };
      final handle = GenerationTaskHandle(taskId: 'task-1');
      final card = await service.create(kind: SettingCardKind.npc, name: '守卫');

      final generated = await service.generate(
        id: card.id,
        instruction: '生成',
        taskHandle: handle,
      );

      expect(gateway.isNpcArgs.single, isTrue);
      expect(gateway.taskHandleArgs.single, same(handle));
      expect(generated.content, contains('## 基础信息'));
      expect(generated.content, isNot(contains('```')));
      expect(generated.content, isNot(contains('"personality"')));
      expect(generated.content.trimLeft().startsWith('{'), isFalse);
    });

    test('character progress arrives as structured stage progress', () async {
      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'personality': '冷静',
      };
      final card =
          await service.create(kind: SettingCardKind.character, name: '林恩');
      final progress = <GenerationStageProgress>[];

      await service.generate(
        id: card.id,
        instruction: '生成',
        onProgress: progress.add,
      );

      expect(progress, isNotEmpty);
      final reported = progress.last;
      expect(reported.stageName, '外貌与体态');
      expect(reported.currentCharacters, 320);
      expect(reported.targetCharacters, 900);
      expect(reported.supplementRound, 1);
    });

    test('saved relations are injected when none were passed explicitly',
        () async {
      final cards = MemorySettingCardRepository();
      final relatedGateway = FakeSettingCardGateway(
        characterResponse: <String, dynamic>{
          'name': '林恩',
          'personality': '冷静',
        },
      );
      final relatedService = SettingCardService(
        repository: cards,
        gateway: relatedGateway,
        relationLoader: (cardId) async => <Map<String, String>>[
          <String, String>{
            'name': '艾琳',
            'profession': '祭司',
            'personality': '温和',
            'background': '同乡',
            'relation': '同伴',
          },
        ],
      );
      final card = await relatedService.create(
        kind: SettingCardKind.character,
        name: '林恩',
      );

      await relatedService.generate(id: card.id, instruction: '生成角色');

      expect(
        relatedGateway.associatedCharacterArgs.single.single['name'],
        '艾琳',
      );
      expect(
        relatedGateway.sources.single,
        contains('以下角色关系已由用户确认，不可改写'),
      );
    });
  });

  group('cancellation', () {
    test('a cancelled character generation never overwrites the card',
        () async {
      final card = await service.create(
        kind: SettingCardKind.character,
        name: '林恩',
        summary: '旧摘要',
        content: '旧正文',
      );
      gateway.characterResponse = <String, dynamic>{
        'name': '林恩',
        'description': '新正文',
      };
      final handle = GenerationTaskHandle(taskId: 'cancel-character');

      await expectLater(
        service.generate(
          id: card.id,
          instruction: '重写',
          taskHandle: handle,
          onProgress: (_) => handle.cancel(),
        ),
        throwsA(isA<SettingCardGenerationCancelledException>()),
      );

      final stored = (await repository.findById(card.id))!;
      expect(stored.content, '旧正文');
      expect(stored.summary, '旧摘要');
      expect(
        stored.metadata.containsKey(SettingCardService.previousSnapshotKey),
        isFalse,
      );
    });

    test('a cancelled worldview generation leaves detail payload untouched',
        () async {
      final card = await service.create(
        kind: SettingCardKind.worldview,
        name: '银月大陆',
        content: '旧世界观正文',
      );
      gateway.worldviewResponse = <String, dynamic>{
        'name': '银月大陆',
        'description': '新概述',
        'detail_json': <String, dynamic>{
          'modules': <String, dynamic>{
            'overview': <String, dynamic>{'summary': '新概览'},
          },
        },
      };
      final handle = GenerationTaskHandle(taskId: 'cancel-worldview');

      await expectLater(
        service.generate(
          id: card.id,
          instruction: '重写',
          taskHandle: handle,
          onProgress: (_) => handle.cancel(),
        ),
        throwsA(isA<SettingCardGenerationCancelledException>()),
      );

      final stored = (await repository.findById(card.id))!;
      expect(stored.content, '旧世界观正文');
      expect(
        stored.metadata.containsKey(SettingCardMarkdownParser.detailJsonKey),
        isFalse,
      );
      expect(
        stored.metadata.containsKey(SettingCardService.previousSnapshotKey),
        isFalse,
      );
    });
  });
}
