import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/adventure/adventure_tracked_state_freezer.dart';
import 'package:lt_dialogue/application/adventure/tracked_state_bootstrap.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/models/supporting_character.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';
import 'package:lt_dialogue/models/worldview_details.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

AdventureConfig _worldConfig() {
  final base = AdventureConfig(
    name: 'Alice',
    supportingCharacters: [_curseBearer('艾莉丝')],
    worldviewSnapshot: {
      'source_id': 'w1',
      'name': '艾尔德兰',
      'detail_json': const WorldviewDetails(
        trackedStateDefinitions: [
          TrackedStateDefinition(
            id: 'war_tension',
            name: '战争紧张度',
            valueKind: RuntimeStateValueKind.integer,
            minimum: 0,
            maximum: 100,
          ),
        ],
      ).toJson(),
    },
  );
  return base.copyWith(
    trackedStateDefinitions: const AdventureTrackedStateFreezer().freeze(base),
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('TrackedStateBootstrap prompt + parse', () {
    test('prompt lists candidates and forbids defaulting', () {
      final config = _worldConfig();
      final candidates = TrackedStateBootstrap.candidatesFor(
        config: config,
        runtimeEntities: const [],
        presentEntityIds: const {'world', 'eileen'},
      );
      final messages = TrackedStateBootstrap.buildMessages(
        openingScene: '边境双方正式交战，烽火连天。',
        candidates: candidates,
      );

      expect(messages.first['content'], contains('开场检测初始化器'));
      expect(messages.first['content'], contains('没有依据就不要输出'));
      expect(messages.last['content'], contains('monitor_id=war_tension'));
    });

    test('parse accepts an evidence-backed set and drops undefined monitors',
        () {
      final config = _worldConfig();
      final diagnostics = <String>[];
      final proposals = TrackedStateBootstrap.parse(
        '{"runtime_state_changes":['
        '{"entity_type":"world","entity_id":"world","change_kind":"primary",'
        '"operation":"set","path":"custom_attributes.war_tension","value":65,'
        '"reason":"帝国正式宣战"},'
        '{"entity_type":"character","entity_id":"eileen","change_kind":"primary",'
        '"operation":"set","path":"custom_attributes.random_mood","value":5,'
        '"reason":"模型自造"}]}',
        config: config,
        diagnostics: diagnostics,
      );

      expect(proposals, hasLength(1));
      expect(proposals.single.path, 'custom_attributes.war_tension');
      expect(diagnostics,
          contains('tracked_state_bootstrap:undefined_monitor:random_mood'));
    });

    test('parse of an unrelated opening yields nothing (absence preserved)',
        () {
      final config = _worldConfig();
      final proposals = TrackedStateBootstrap.parse(
        '{"runtime_state_changes":[]}',
        config: config,
      );

      expect(proposals, isEmpty);
    });
  });

  group('TrackedStateBootstrap commit', () {
    late Directory tempDir;
    late IAdventureRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('lt_bootstrap_');
      DatabaseService.customDbDir = tempDir.path;
      await DatabaseService.resetDatabase();
      repository =
          AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    });

    tearDown(() async {
      await DatabaseService.resetDatabase();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('initializes an evidenced monitor through an atomic mutation',
        () async {
      final config = _worldConfig();
      final adventureId = await repository.createAdventure('Bootstrap', config);
      await repository.seedRuntimeEntity(
        adventureId: adventureId,
        branchId: 0,
        entityType: RuntimeEntityType.world,
        entityId: 'world',
      );

      final proposals = TrackedStateBootstrap.parse(
        '{"runtime_state_changes":['
        '{"entity_type":"world","entity_id":"world","change_kind":"primary",'
        '"operation":"set","path":"custom_attributes.war_tension","value":65,'
        '"reason":"开场边境正式交战"}]}',
        config: config,
      );

      await repository.commitRuntimeMutation(RuntimeStateMutation(
        requestId: 'bootstrap-1',
        adventureId: adventureId,
        branchId: 0,
        draft: RuntimeStateCommitDraft(
          expectedRevision: 0,
          changes: proposals,
          summary: 'Opening tracked state bootstrap',
          source: RuntimeEventSource.systemRule,
          causeType: 'opening_bootstrap',
        ),
        causeType: 'opening_bootstrap',
      ));

      final world = (await repository.getRuntimeEntities(adventureId, 0))
          .singleWhere((e) => e.entityType == RuntimeEntityType.world);
      expect(world.overlay['custom_attributes.war_tension'], 65);
      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 1);
    });

    test('does not fabricate a value when the opening has no evidence',
        () async {
      final config = _worldConfig();
      final adventureId = await repository.createAdventure('Bootstrap', config);
      await repository.seedRuntimeEntity(
        adventureId: adventureId,
        branchId: 0,
        entityType: RuntimeEntityType.world,
        entityId: 'world',
      );

      final proposals = TrackedStateBootstrap.parse(
        '{"runtime_state_changes":[]}',
        config: config,
      );
      expect(proposals, isEmpty);

      // No commit is issued for an evidence-free opening.
      expect((await repository.getRuntimeHead(adventureId, 0)).revision, 0);
      final world = (await repository.getRuntimeEntities(adventureId, 0))
          .singleWhere((e) => e.entityType == RuntimeEntityType.world);
      expect(
          world.overlay.containsKey('custom_attributes.war_tension'), isFalse);
    });
  });
}

SupportingCharacter _curseBearer(String name) => SupportingCharacter(
      id: 'eileen',
      name: name,
      trackedStateDefinitions: const [
        TrackedStateDefinition(
          id: 'curse',
          name: '诅咒侵蚀',
          valueKind: RuntimeStateValueKind.integer,
          minimum: 0,
          maximum: 100,
        ),
      ],
    );
