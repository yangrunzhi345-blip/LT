import 'package:flutter_test/flutter_test.dart';
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
}
