import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_library_runtime.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';

import '../../helpers/setting_card_fakes.dart';

final class _FakeFallback implements ResourceLibraryRuntime {
  _FakeFallback(this.items);

  List<ResourceLibraryItem> items;
  int trashCalls = 0;

  @override
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode) async =>
      items;

  @override
  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  }) async {
    trashCalls++;
    items = items.where((candidate) => candidate.id != item.id).toList();
    return const ResourceOperationResult.success();
  }

  @override
  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  }) async =>
      'legacy-created';
}

ResourceLibraryItem _legacyItem(String id, {String type = 'character'}) =>
    ResourceLibraryItem(
      id: id,
      type: type == 'worldview'
          ? ResourceType.worldview
          : type == 'npc'
              ? ResourceType.npc
              : ResourceType.character,
      name: '旧 $id',
      summary: '',
      updatedAt: '2025-01-01T00:00:00.000',
      status: ResourceDisplayStatus.saved,
      isStudioAvailable: true,
    );

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

  test('cards replace their migrated legacy row in the list', () async {
    repository.cards['res_legacy_character_cards_c1'] = const SettingCard(
      id: 'res_legacy_character_cards_c1',
      kind: SettingCardKind.character,
      name: '迁移角色',
      content: '正文',
      legacyId: 'c1',
      updatedAt: '2026-01-01T00:00:00.000',
      createdAt: '2026-01-01T00:00:00.000',
    );
    final runtime = SettingCardLibraryRuntime(
      service: service,
      fallback: _FakeFallback(<ResourceLibraryItem>[_legacyItem('c1')]),
    );

    final items = await runtime.load(ResourceLibraryMode.adventure);

    expect(items, hasLength(1));
    expect(items.single.id, 'res_legacy_character_cards_c1');
    expect(items.single.isSettingCard, isTrue);
  });

  test('legacy rows without a card stay visible during the transition',
      () async {
    final runtime = SettingCardLibraryRuntime(
      service: service,
      fallback: _FakeFallback(<ResourceLibraryItem>[_legacyItem('old-1')]),
    );

    final items = await runtime.load(ResourceLibraryMode.adventure);

    expect(items.map((item) => item.id), <String>['old-1']);
    expect(items.single.isSettingCard, isFalse);
  });

  test('card items project the card fields and never claim Studio support',
      () async {
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
    final runtime = SettingCardLibraryRuntime(
      service: service,
      fallback: _FakeFallback(const <ResourceLibraryItem>[]),
    );

    final items = await runtime.load(ResourceLibraryMode.adventure);

    expect(items.single.type, ResourceType.worldview);
    expect(items.single.summary, '大陆概述');
    expect(items.single.isConsumable, isTrue);
    expect(items.single.isStudioAvailable, isFalse);
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
    final runtime = SettingCardLibraryRuntime(
      service: service,
      fallback: _FakeFallback(const <ResourceLibraryItem>[]),
    );

    final items = await runtime.load(ResourceLibraryMode.conversation);

    expect(items, isEmpty);
  });

  test('moveToTrash soft deletes a card without touching the fallback',
      () async {
    repository.cards['card-1'] = const SettingCard(
      id: 'card-1',
      kind: SettingCardKind.character,
      name: '林恩',
      updatedAt: '2026-01-01T00:00:00.000',
      createdAt: '2026-01-01T00:00:00.000',
    );
    final fallback = _FakeFallback(const <ResourceLibraryItem>[]);
    final runtime = SettingCardLibraryRuntime(
      service: service,
      fallback: fallback,
    );

    final result = await runtime.moveToTrash(
      item: _legacyItem('card-1'),
      mode: ResourceLibraryMode.adventure,
    );

    expect(result.success, isTrue);
    expect(fallback.trashCalls, 0);
    expect(repository.cards['card-1']!.isDeleted, isTrue);
  });

  test('moveToTrash delegates when the item is not a card', () async {
    final fallback = _FakeFallback(<ResourceLibraryItem>[_legacyItem('old-1')]);
    final runtime = SettingCardLibraryRuntime(
      service: service,
      fallback: fallback,
    );

    await runtime.moveToTrash(
      item: _legacyItem('old-1'),
      mode: ResourceLibraryMode.adventure,
    );

    expect(fallback.trashCalls, 1);
  });

  test('createManual writes a card with the current mode', () async {
    final runtime = SettingCardLibraryRuntime(
      service: service,
      fallback: _FakeFallback(const <ResourceLibraryItem>[]),
    );

    final id = await runtime.createManual(
      type: ResourceType.npc,
      name: '北门守卫',
      summary: '守序',
      mode: ResourceLibraryMode.conversation,
    );

    expect(id, 'new-card');
    final card = repository.cards['new-card']!;
    expect(card.kind, SettingCardKind.npc);
    expect(card.mode, 'conversation');
  });
}
