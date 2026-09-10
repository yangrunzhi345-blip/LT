import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/application/adventure/adventure_setup_use_case.dart';
import 'package:lt_dialogue/controllers/adventure_setup_controller.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';

/// Use case whose three loaders return externally controlled futures so a test
/// can force any completion order across overlapping `loadInitialData` calls.
class _ControllableUseCase extends AdventureSetupUseCase {
  _ControllableUseCase(super.repository);

  final List<Completer<List<Map<String, dynamic>>>> worldview = [];
  final List<Completer<List<Map<String, dynamic>>>> characters = [];
  final List<Completer<List<Map<String, dynamic>>>> npcs = [];

  @override
  Future<List<Map<String, dynamic>>> loadWorldviewPresets() {
    final completer = Completer<List<Map<String, dynamic>>>();
    worldview.add(completer);
    return completer.future;
  }

  @override
  Future<List<Map<String, dynamic>>> loadCharacterCards() {
    final completer = Completer<List<Map<String, dynamic>>>();
    characters.add(completer);
    return completer.future;
  }

  @override
  Future<List<Map<String, dynamic>>> loadNpcCards() {
    final completer = Completer<List<Map<String, dynamic>>>();
    npcs.add(completer);
    return completer.future;
  }
}

Map<String, dynamic> _row(String id) => {'id': id, 'name': id};

/// Completes the loaders of one call with the given rows / error.
void _completeLoad(
  _ControllableUseCase useCase,
  int index, {
  required String tag,
  String? worldviewError,
}) {
  useCase.characters[index].complete([_row('$tag-char')]);
  useCase.npcs[index].complete([_row('$tag-npc')]);
  if (worldviewError != null) {
    useCase.worldview[index].completeError(StateError(worldviewError));
  } else {
    useCase.worldview[index].complete([_row('$tag-world')]);
  }
}

void main() {
  late _ControllableUseCase useCase;
  late AdventureSetupController controller;

  setUp(() {
    // The fake overrides every loader, so the repository is never queried.
    useCase = _ControllableUseCase(
        LibraryRepositoryImpl(getDb: () => throw StateError('unused')));
    controller = AdventureSetupController(useCase: useCase);
  });

  test('older load cannot overwrite a newer one', () async {
    final older = controller.loadInitialData();
    final newer = controller.loadInitialData();

    _completeLoad(useCase, 1, tag: 'B');
    await newer;

    _completeLoad(useCase, 0, tag: 'A');
    await older;

    expect(controller.worldviewPresets.single['id'], 'B-world');
    expect(controller.characterCards.single['id'], 'B-char');
    expect(controller.npcCards.single['id'], 'B-npc');
    expect(controller.loading, isFalse);
  });

  test('stale error completing after a newer success is ignored', () async {
    final older = controller.loadInitialData();
    final newer = controller.loadInitialData();

    _completeLoad(useCase, 1, tag: 'B');
    await newer;
    expect(controller.worldviewError, isNull);

    _completeLoad(useCase, 0, tag: 'A', worldviewError: 'worldview A failed');
    await older;

    expect(controller.worldviewError, isNull);
    expect(controller.worldviewPresets.single['id'], 'B-world');
  });

  test('stale success completing after a newer error cannot clear it',
      () async {
    final older = controller.loadInitialData();
    final newer = controller.loadInitialData();

    _completeLoad(useCase, 1, tag: 'B', worldviewError: 'worldview B failed');
    await newer;
    expect(controller.worldviewError, isNotNull);
    expect(controller.characterCards.single['id'], 'B-char');

    _completeLoad(useCase, 0, tag: 'A');
    await older;

    expect(controller.worldviewError, contains('B failed'));
    expect(controller.characterCards.single['id'], 'B-char');
  });

  test('loading stays true until the newest load completes', () async {
    final older = controller.loadInitialData();
    final newer = controller.loadInitialData();
    expect(controller.loading, isTrue);

    _completeLoad(useCase, 0, tag: 'A');
    await older;
    // The stale completion must not flip the flag while B is still running.
    expect(controller.loading, isTrue);

    _completeLoad(useCase, 1, tag: 'B');
    await newer;
    expect(controller.loading, isFalse);
  });

  test('reset during an in-flight load prevents later repopulation', () async {
    final pending = controller.loadInitialData();
    controller.reset();
    expect(controller.loading, isFalse);

    _completeLoad(useCase, 0, tag: 'A');
    await pending;

    expect(controller.worldviewPresets, isEmpty);
    expect(controller.characterCards, isEmpty);
    expect(controller.npcCards, isEmpty);
    expect(controller.loading, isFalse);
  });

  test('dispose during an in-flight load does not notify', () async {
    var notifications = 0;
    controller.addListener(() => notifications++);

    final pending = controller.loadInitialData();
    final afterStart = notifications;

    controller.dispose();
    _completeLoad(useCase, 0, tag: 'A');

    // Completing a disposed controller must not throw or notify listeners.
    await expectLater(pending, completes);
    expect(notifications, afterStart);
  });
}
