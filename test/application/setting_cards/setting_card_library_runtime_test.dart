import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_library_runtime.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';

import '../../helpers/setting_card_fakes.dart';

void main() {
  late MemorySettingCardRepository repository;
  late FakeSettingCardGateway gateway;
  late SettingCardService service;

  setUp(() {
    repository = MemorySettingCardRepository();
    gateway = FakeSettingCardGateway();
    service = SettingCardService(
      repository: repository,
      gateway: gateway,
      clock: () => '2026-08-01T00:00:00.000',
      idGenerator: () => 'new-card',
    );
  });

  test('migrated card is visible in the library', () async {
    repository.cards['res_legacy_character_cards_c1'] = const SettingCard(
      id: 'res_legacy_character_cards_c1',
      kind: SettingCardKind.character,
      name: '迁移角色',
      content: '正文',
      legacyId: 'c1',
      mode: 'adventure',
      updatedAt: '2026-01-01T00:00:00.000',
      createdAt: '2026-01-01T00:00:00.000',
    );
    final runtime = SettingCardLibraryRuntime(service: service);

    final items = await runtime.load(ResourceLibraryMode.adventure);

    expect(items, hasLength(1));
    expect(items.single.id, 'res_legacy_character_cards_c1');
  });

  test('an empty card store yields an empty library', () async {
    final runtime = SettingCardLibraryRuntime(service: service);

    final items = await runtime.load(ResourceLibraryMode.adventure);

    expect(items, isEmpty);
  });

  test('card items project the card fields', () async {
    repository.cards['card-w'] = const SettingCard(
      id: 'card-w',
      kind: SettingCardKind.worldview,
      name: '银月大陆',
      summary: '大陆概述',
      content: '# 正文',
      mode: 'adventure',
      originWorldviewId: 'w-root',
      updatedAt: '2026-02-01T00:00:00.000',
      createdAt: '2026-01-01T00:00:00.000',
    );
    final runtime = SettingCardLibraryRuntime(service: service);

    final items = await runtime.load(ResourceLibraryMode.adventure);

    expect(items.single.type, ResourceType.worldview);
    expect(items.single.summary, '大陆概述');
    expect(items.single.isConsumable, isTrue);
    expect(items.single.originWorldviewId, 'w-root');
  });

  test('conversation mode hides adventure-only cards', () async {
    repository.cards['a'] = const SettingCard(
      id: 'a',
      kind: SettingCardKind.character,
      name: '冒险角色',
      mode: 'adventure',
      updatedAt: '2026-01-01T00:00:00.000',
      createdAt: '2026-01-01T00:00:00.000',
    );
    final runtime = SettingCardLibraryRuntime(service: service);

    final items = await runtime.load(ResourceLibraryMode.conversation);

    expect(items, isEmpty);
  });
}
