import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/core/localization/app_error_localizer.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/errors/app_error.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/resource_library_mode.dart';
import 'package:lt_dialogue/services/repositories/library_repository.dart';
import 'package:mocktail/mocktail.dart';

/// R05-A regression: every async publish is bound to a request generation and
/// the target identity, so a late completion or late error of an older request
/// can never overwrite the current one.
///
/// The Resource Studio surfaces (section control, capacity, revision and the
/// streaming Studio runtime) were removed in Phase 5c, so their ownership cases
/// no longer have an implementation to bind to. The surviving cases cover the
/// library CRUD controller, whose serialised mutation queue and error-surface
/// ownership are still part of the current architecture.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('R05-A ResourceCrudController', () {
    late _MockLibraryRepository repository;

    setUp(() {
      repository = _MockLibraryRepository();
      registerFallbackValue(ResourceLibraryMode.adventure);
    });

    test('disposed mutation returns a typed, locale-neutral failure', () async {
      final controller = ResourceCrudController(repository: repository);
      controller.dispose();

      final result = await controller.deleteWorldviewPreset('wv-1');

      expect(result.success, isFalse);
      expect(result.error?.code, AppErrorCode.unknown);
      expect(result.errorMessage, isEmpty);
      final en = lookupAppLocalizations(const Locale('en'));
      final zh = lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      );
      expect(localizeAppError(en, result.error!), en.errorUnknown);
      expect(localizeAppError(zh, result.error!), zh.errorUnknown);
      expect(en.errorUnknown, isNot(zh.errorUnknown));
      verifyNever(() => repository.deleteWorldviewPreset(
            any(),
            mode: any(named: 'mode'),
          ));
    });

    test('A5 concurrent deletes are serialised, never interleaved', () async {
      final gateA = Completer<void>();
      final gateB = Completer<void>();
      final callLog = <String>[];
      when(() =>
              repository.deleteWorldviewPreset(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async {
        callLog.add('enter-a');
        await gateA.future;
        callLog.add('exit-a');
      });
      when(() =>
              repository.deleteCharacterCard(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async {
        callLog.add('enter-b');
        await gateB.future;
        callLog.add('exit-b');
      });

      final controller = ResourceCrudController(repository: repository);
      final deleteA = controller.deleteWorldviewPreset('wv-1');
      final deleteB = controller.deleteCharacterCard('card-1');
      await pumpEventQueue();
      expect(callLog, ['enter-a'],
          reason: 'B must wait until A finished (serialise policy)');

      gateA.complete();
      await pumpEventQueue();
      expect(callLog, ['enter-a', 'exit-a', 'enter-b']);
      gateB.complete();

      final resultA = await deleteA;
      final resultB = await deleteB;
      expect(resultA.success, isTrue);
      expect(resultB.success, isTrue);
    });

    test(
        'A6 double delete of the same target converges without a second '
        'overlapping write', () async {
      var inFlight = 0;
      var overlapDetected = false;
      final gate = Completer<void>();
      when(() => repository.deleteNpcCard(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async {
        if (inFlight > 0) overlapDetected = true;
        inFlight += 1;
        await gate.future;
        inFlight -= 1;
      });

      final controller = ResourceCrudController(repository: repository);
      final first = controller.deleteNpcCard('npc-1');
      final second = controller.deleteNpcCard('npc-1');
      gate.complete();
      final results = await Future.wait([first, second]);

      expect(overlapDetected, isFalse,
          reason: 'serialisation must prevent overlapping destructive writes');
      for (final result in results) {
        expect(result.success, isTrue);
      }
    });

    test('a failed mutation does not stall the serialised queue', () async {
      when(() =>
              repository.deleteWorldviewPreset(any(), mode: any(named: 'mode')))
          .thenThrow(StateError('boom'));
      when(() => repository.deleteNpcCard(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async {});

      final controller = ResourceCrudController(repository: repository);
      final failing = controller.deleteWorldviewPreset('wv-1');
      final following = controller.deleteNpcCard('npc-1');

      final failure = await failing;
      final success = await following;
      expect(failure.success, isFalse);
      expect(success.success, isTrue);
      expect(controller.error, isNull,
          reason: 'the second operation must own the error surface');
    });
  });
}

class _MockLibraryRepository extends Mock implements ILibraryRepository {}
