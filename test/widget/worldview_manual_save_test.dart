import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/resource_library/edit_drafts.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_service.dart';
import 'package:lt_dialogue/controllers/resource_crud_controller.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/setting_card_repository_impl.dart';

/// Simple-mode worldviews must have a 200–500 character description.
final String _descriptionA = '测试世界观描述段落，' * 24;
final String _descriptionB = '更新后的世界观描述，' * 24;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late LibraryRepositoryImpl repository;
  late SettingCardRepositoryImpl cardRepository;
  late ResourceCrudController crud;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_worldview_save_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    await DatabaseService.database;

    repository = LibraryRepositoryImpl(getDb: () => DatabaseService.database);
    cardRepository =
        SettingCardRepositoryImpl(getDb: () => DatabaseService.database);
    crud = ResourceCrudController(
      repository: repository,
      cardMirror: LegacyCardMirror(repository: cardRepository),
    );
    addTearDown(crud.dispose);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    DatabaseService.customDbDir = null;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('creating a worldview persists through saveWorldviewDraft', () async {
    final draft = WorldviewEditDraft(
      name: '测试世界观甲',
      description: _descriptionA,
    );

    final result = await crud.saveWorldviewDraft(draft);
    expect(result.success, isTrue, reason: result.errorMessage ?? '');
    // The controller pins the generated id so a second save updates in place.
    expect(draft.id, isNotNull);

    final rows = await repository.getWorldviewPresets();
    final saved = rows.firstWhere((row) => row['name'] == '测试世界观甲');
    expect(saved['description'], _descriptionA);
    expect(saved['id'], draft.id);
  });

  test('the saved worldview is mirrored into the setting card store', () async {
    final draft = WorldviewEditDraft(
      name: '镜像世界观',
      description: _descriptionA,
    );

    final result = await crud.saveWorldviewDraft(draft);
    expect(result.success, isTrue, reason: result.errorMessage ?? '');

    final card = await cardRepository.findById(
      LegacyCardMirror.cardIdFor(SettingCardKind.worldview, draft.id!),
    );
    expect(card, isNotNull);
    expect(card!.name, '镜像世界观');
    expect(card.content, contains(_descriptionA.trim()));
  });

  test('repeated saves update in place, never duplicating the resource',
      () async {
    final draft = WorldviewEditDraft(
      name: '唯一世界观',
      description: _descriptionA,
    );
    await crud.saveWorldviewDraft(draft);
    final id = draft.id;

    draft.description = _descriptionB;
    final second = await crud.saveWorldviewDraft(draft);
    expect(second.success, isTrue, reason: second.errorMessage ?? '');
    expect(draft.id, id, reason: 'the pinned id survives a second save');

    final rows = (await repository.getWorldviewPresets())
        .where((row) => row['name'] == '唯一世界观')
        .toList();
    expect(rows, hasLength(1),
        reason: 'repeated saves must not duplicate the resource');
    expect(rows.single['description'], _descriptionB);
  });

  test('an invalid draft is reported as failure and never persisted', () async {
    final draft = WorldviewEditDraft(
      name: '待失败世界观',
      description: '太短',
    );

    final result = await crud.saveWorldviewDraft(draft);
    expect(result.success, isFalse);
    expect(result.errorMessage, isNotEmpty);

    final rows = (await repository.getWorldviewPresets())
        .where((row) => row['name'] == '待失败世界观');
    expect(rows, isEmpty);
  });
}
