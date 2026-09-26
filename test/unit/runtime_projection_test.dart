import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/models/adventure_runtime_state.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory directory;
  late AdventureRepositoryImpl repository;
  late int adventureId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lt_projection_test_');
    DatabaseService.customDbDir = directory.path;
    await DatabaseService.resetDatabase();
    repository = AdventureRepositoryImpl(getDb: () => DatabaseService.database);
    adventureId = await repository.createAdventure(
      'Projection test',
      AdventureConfig(name: 'Test'),
    );
    final db = await DatabaseService.database;
    for (var revision = 1; revision <= 3; revision++) {
      final commitId = 'commit-$revision';
      await db.insert('adventure_state_commits', {
        'id': commitId,
        'adventure_id': adventureId,
        'branch_id': 0,
        'request_id': 'request-$revision',
        'parent_commit_id': revision == 1 ? null : 'commit-${revision - 1}',
        'revision': revision,
        'summary': 'revision $revision',
        'cause_type': 'scene_dialogue',
        'created_at': '2026-01-01T00:00:0$revision.000Z',
      });
      final after = revision == 1 ? 10 : (revision == 2 ? 20 : null);
      final event = {
        'schema_version': 1,
        'event_id': '$commitId-event-0',
        'event_type_id': revision == 1 ? 'target_event' : 'other_event',
        'source': 'aiProposal',
        'importance': 'normal',
        'visibility': 'user',
        'occurred_at': '2026-01-01T00:00:0$revision.000Z',
        'parameters': {'path': 'hp'},
      };
      await db.insert('adventure_state_changes', {
        'id': '$commitId-change-0',
        'commit_id': commitId,
        'change_index': 0,
        'entity_type': 'character',
        'entity_id': 'hero',
        'change_kind': 'primary',
        'operation': revision == 3 ? 'remove' : 'set',
        'path': 'hp',
        'before_json': jsonEncode(revision == 1
            ? 5
            : revision == 2
                ? 10
                : 20),
        'after_json': jsonEncode(after),
        'reason': 'test',
        'provenance_json': jsonEncode({'event': event}),
      });
    }
    await db.insert('adventure_state_commits', {
      'id': 'branch-commit-1',
      'adventure_id': adventureId,
      'branch_id': 1,
      'request_id': 'branch-request-1',
      'revision': 1,
      'summary': 'other branch',
      'cause_type': 'scene_dialogue',
      'created_at': '2026-01-01T00:01:00.000Z',
    });
    await db.insert('adventure_state_changes', {
      'id': 'branch-change-1',
      'commit_id': 'branch-commit-1',
      'change_index': 0,
      'entity_type': 'character',
      'entity_id': 'hero',
      'change_kind': 'primary',
      'operation': 'set',
      'path': 'hp',
      'before_json': jsonEncode(5),
      'after_json': jsonEncode(99),
      'reason': 'branch test',
      'provenance_json': '{}',
    });
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('replays set and remove at an exact revision', () async {
    final atOne = await repository.getRuntimeStateAtRevision(
      adventureId: adventureId,
      branchId: 0,
      revision: 1,
    );
    final atTwo = await repository.getRuntimeStateAtRevision(
      adventureId: adventureId,
      branchId: 0,
      revision: 2,
    );
    final atThree = await repository.getRuntimeStateAtRevision(
      adventureId: adventureId,
      branchId: 0,
      revision: 3,
    );
    expect(atOne.entities['character:hero']!.overlay['hp'], 10);
    expect(atTwo.entities['character:hero']!.overlay['hp'], 20);
    expect(atThree.entities['character:hero']!.overlay, isEmpty);
  });

  test('timeline groups changes by commit and uses a revision cursor',
      () async {
    final page = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 0,
      limit: 2,
    );
    expect(page.map((entry) => entry.revision), [3, 2]);
    expect(page.every((entry) => entry.events.length == 1), isTrue);
    final older = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 0,
      beforeRevision: page.last.revision,
      limit: 2,
    );
    expect(older.map((entry) => entry.revision), [1]);
  });

  test('replay and timeline stay isolated by branch', () async {
    final branchZero = await repository.getRuntimeStateAtRevision(
      adventureId: adventureId,
      branchId: 0,
      revision: 1,
    );
    final branchOne = await repository.getRuntimeStateAtRevision(
      adventureId: adventureId,
      branchId: 1,
      revision: 1,
    );
    expect(branchZero.entities['character:hero']!.overlay['hp'], 10);
    expect(branchOne.entities['character:hero']!.overlay['hp'], 99);
    final timeline = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 0,
      limit: 10,
    );
    expect(timeline.every((entry) => entry.branchId == 0), isTrue);
    expect(timeline.map((entry) => entry.commitId),
        isNot(contains('branch-commit-1')));
    final legacyTimeline = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 1,
      limit: 1,
    );
    expect(legacyTimeline.single.isLegacy, isTrue);
    expect(legacyTimeline.single.events, isEmpty);
  });

  test('event type filtering happens before the bounded commit window',
      () async {
    final filtered = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 0,
      eventTypeId: 'target_event',
      limit: 1,
    );
    expect(filtered.map((entry) => entry.revision), [1]);
    expect(filtered.single.diffs, hasLength(1));
    expect(filtered.single.events.single.eventTypeId, 'target_event');
  });

  test('event type filtering composes with cursor and entity scope', () async {
    final filtered = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 0,
      beforeRevision: 3,
      entityId: 'hero',
      eventTypeId: 'target_event',
      limit: 1,
    );
    expect(filtered.map((entry) => entry.revision), [1]);
    final legacy = await repository.getRuntimeTimeline(
      adventureId: adventureId,
      branchId: 1,
      eventTypeId: 'target_event',
      limit: 1,
    );
    expect(legacy, isEmpty);
  });

  test('turn history groups accepted changes and stays branch local', () async {
    final db = await DatabaseService.database;
    await db.insert('scene_dialogue_turns', {
      'request_id': 'request-1',
      'adventure_id': adventureId,
      'branch_id': 0,
      'created_at': '2026-01-01T00:00:01.000Z',
      'assistant_client_message_id': 'assistant-1',
    });
    await db.insert('scene_dialogue_turns', {
      'request_id': 'request-2',
      'adventure_id': adventureId,
      'branch_id': 0,
      'created_at': '2026-01-01T00:00:02.000Z',
      'assistant_client_message_id': 'assistant-2',
    });
    await db.insert('adventure_state_commits', {
      'id': 'request-1-follow-up',
      'adventure_id': adventureId,
      'branch_id': 0,
      'request_id': 'request-1-follow-up',
      'revision': 4,
      'cause_type': 'system_rule',
      'cause_ref': 'request-1',
      'created_at': '2026-01-01T00:00:03.000Z',
    });
    await db.insert('adventure_state_changes', {
      'id': 'request-1-follow-up-change',
      'commit_id': 'request-1-follow-up',
      'change_index': 0,
      'entity_type': 'world',
      'entity_id': 'north-gate',
      'change_kind': 'derived',
      'operation': 'set',
      'path': 'status',
      'before_json': jsonEncode('quiet'),
      'after_json': jsonEncode('alert'),
      'reason': 'system rule',
      'provenance_json': '{}',
    });
    final page = await repository.getTurnStateHistory(
      adventureId: adventureId,
      branchId: 0,
      limit: 10,
    );
    expect(page.map((turn) => turn.turnNumber), [2, 1]);
    expect(page.first.changes.single.path, 'hp');
    expect(page.last.changes, hasLength(2));
    final worldOnly = await repository.getTurnStateHistory(
      adventureId: adventureId,
      branchId: 0,
      entityTypes: {RuntimeEntityType.world},
      limit: 1,
    );
    expect(worldOnly.single.turnNumber, 1);
    expect(worldOnly.single.changes.single.entityType, RuntimeEntityType.world);
    expect(page.first.revisionStart, 2);
    final older = await repository.getTurnStateHistory(
      adventureId: adventureId,
      branchId: 0,
      beforeTurnRowId: page.last.turnRowId,
      limit: 10,
    );
    expect(older, isEmpty);
  });

  test('turn message projection returns the paired user and assistant text',
      () async {
    final db = await DatabaseService.database;
    await db.insert('messages', {
      'adventure_id': adventureId,
      'branch_id': 0,
      'role': 'user',
      'content': 'Open the gate',
      'timestamp': '2026-01-01T00:00:00.000Z',
      'client_message_id': 'user-1',
    });
    await db.insert('messages', {
      'adventure_id': adventureId,
      'branch_id': 0,
      'role': 'assistant',
      'content': 'The gate opens.',
      'timestamp': '2026-01-01T00:00:01.000Z',
      'client_message_id': 'assistant-1',
    });
    final messages = await repository.getTurnMessages(
      adventureId: adventureId,
      branchId: 0,
      assistantMessageId: 'assistant-1',
    );
    expect(messages.map((message) => message.content),
        ['Open the gate', 'The gate opens.']);
  });
}
