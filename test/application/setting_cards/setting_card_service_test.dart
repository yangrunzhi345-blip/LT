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
}
