import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_markdown_parser.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_reference_input.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';

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

    final stages = <String>[];
    final card = await service.generate(
      id: 'card-1',
      instruction: '生成一个奇幻大陆',
      onProgress: (_, __, name) => stages.add(name),
    );

    expect(gateway.worldviewCalls, 1);
    expect(gateway.sources.single, '生成一个奇幻大陆');
    expect(stages, isNotEmpty);
    expect(card.name, '银月大陆');
    expect(card.summary, '被月光笼罩的大陆');
    expect(card.content, contains('## description'));
    expect(card.content, contains('被月光笼罩的大陆'));
    expect(card.content, contains('## modules'));
    expect(card.content, contains('三百年前的战争'));
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
}
