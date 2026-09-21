import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/application/adventure/adventure_ai_use_case.dart';
import 'package:lt_dialogue/controllers/adventure_ai_controller.dart';
import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/core/widgets/app_text_field.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/assembly_create_page.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/providers/chat_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/repositories/adventure_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/world_entry_repository_impl.dart';

/// P0 回归：装配流水线必须重新提供「AI 自动编写序章与初始行动分支」能力，
/// 并且真实携带当前装配上下文（用户要求 / 世界观 / 角色卡 / 角色关系 / NPC）。
///
/// 断言的是「传给 generateOpening 的上下文」与「写回 UI 的结果」，而不是
/// 「某个回调被调用过」。
class _KeyConfiguredChatProvider extends ChatProvider {
  _KeyConfiguredChatProvider()
      : super.withRepos(
          adventureRepo:
              AdventureRepositoryImpl(getDb: () => DatabaseService.database),
          worldEntryRepo:
              WorldEntryRepositoryImpl(getDb: () => DatabaseService.database),
          libraryRepo:
              LibraryRepositoryImpl(getDb: () => DatabaseService.database),
          settingsRepo:
              SettingsRepositoryImpl(getDb: () => DatabaseService.database),
        );

  @override
  bool get isKeyConfigured => true;
}

/// Records every argument handed to the single adventure AI authority and
/// replays a canned prologue (or a normalized failure).
class _RecordingAiController extends AdventureAiController {
  _RecordingAiController({required super.useCase});

  int calls = 0;
  Map<String, Object?>? lastArgs;
  Map<String, String>? nextResult;
  String? nextError;

  @override
  String? get errorMessage => nextError ?? super.errorMessage;

  @override
  Future<Map<String, String>?> generateOpening({
    required String userPrompt,
    String worldview = '',
    String protagonistName = '',
    String protagonistRole = '',
    String protagonistPersonality = '',
    String protagonistBackground = '',
    String protagonistBodyDescription = '',
    String protagonistAppearance = '',
    List<Map<String, String>> selectedCharacters = const [],
    List<Map<String, String>> characterRelationships = const [],
    List<Map<String, String>> npcs = const [],
  }) async {
    calls++;
    lastArgs = <String, Object?>{
      'userPrompt': userPrompt,
      'worldview': worldview,
      'protagonistName': protagonistName,
      'protagonistRole': protagonistRole,
      'protagonistPersonality': protagonistPersonality,
      'protagonistBackground': protagonistBackground,
      'selectedCharacters': selectedCharacters,
      'characterRelationships': characterRelationships,
      'npcs': npcs,
    };
    if (nextError != null) return null;
    return nextResult;
  }
}

AdventureConfig _assemblyConfig() => AdventureConfig(
      worldview: '幽暗森林',
      name: '莉安',
      gender: '女',
      age: '22',
      protagonistClass: '游侠',
      personality: '敏锐冷静',
      protagonistBackground: '来自北境的荒野猎手',
      selectedCharacters: [
        AdventureSelectedCharacter(
          id: 'p1',
          characterId: 'p1',
          characterName: '莉安',
          isProtagonist: true,
          narrativeRole: AdventureCharacterRole.protagonist,
          characterCardJson: const {
            'name': '莉安',
            'gender': '女',
            'age': '22',
            'profession': '游侠',
            'personality': '敏锐冷静',
            'description': '来自北境的荒野猎手',
          },
        ),
        AdventureSelectedCharacter(
          id: 'c2',
          characterId: 'c2',
          characterName: '凯尔',
          isProtagonist: false,
          narrativeRole: AdventureCharacterRole.companion,
          sortOrder: 1,
          characterCardJson: const {
            'name': '凯尔',
            'profession': '盾卫',
            'personality': '憨直忠诚',
            'description': '莉安并肩多年的旧识',
          },
        ),
      ],
      characterRelationships: [
        AdventureCharacterRelationship(
          id: 'r1',
          sourceCharacterId: 'p1',
          targetCharacterId: 'c2',
          relationType: AdventureRelationType.companion,
          description: '并肩多年的伙伴',
        ),
      ],
      npcSnapshots: [
        AdventureNpcSnapshot(
          assetId: 'npc_innkeeper',
          name: '老约克',
          npcJson: const {
            'name': '老约克',
            'role': '酒馆老板',
            'personality': '热情健谈',
          },
        ),
      ],
      openingScene: '用户手写的初始序章',
      openingOptions: ['用户手写的分支'],
    );

String _textOf(WidgetTester tester, Key key) {
  final field = tester.widget<AppTextField>(find.byKey(key));
  return field.controller?.text ?? '';
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'deepseek_api_key': 'test', 'openai_api_key': 'test'});
    tempDir = await Directory.systemTemp.createTemp('lt_opening_ai_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    final db = await DatabaseService.database;
    final now = DateTime.now().toIso8601String();
    await db.insert('npc_cards', {
      'id': 'npc_innkeeper',
      'name': '老约克',
      'json_data': jsonEncode({
        'name': '老约克',
        'role': '酒馆老板',
        'personality': '热情健谈',
      }),
      'source': '测试',
      'matching_worldview_id': '',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<_RecordingAiController> pumpAssembly(
    WidgetTester tester, {
    Size viewport = const Size(1100, 2600),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      chatProvider.overrideWith((ref) => _KeyConfiguredChatProvider()),
      adventureAiControllerProvider.overrideWith(
        (ref) => _RecordingAiController(
          useCase: AdventureAiUseCase(ref.read(llmGatewayProvider)),
        ),
      ),
    ]);
    addTearDown(container.dispose);
    final ai =
        container.read(adventureAiControllerProvider) as _RecordingAiController;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AssemblyCreatePage(
            onStartAdventure: (_) async {},
            initialConfig: _assemblyConfig(),
            initialWorldviewDesc: '终年不见天日的古老森林',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 跳到序章分支阶段。
    await tester.tap(find.text('3. 序章分支'));
    await tester.pumpAndSettle();
    return ai;
  }

  testWidgets(
      'AI generation receives the complete assembly context and writes '
      'the prologue back into the editable fields', (tester) async {
    final ai = await pumpAssembly(tester);
    ai.nextResult = {
      'scene': '雨水沿着破碎的船舷滑落，莉安在废弃码头的阴影中睁开了眼。',
      'options': '1 调查四周的脚印\n2 呼唤同伴凯尔\n3 立即离开码头',
    };

    await tester.enterText(
      find.byKey(const Key('assembly-opening-ai-prompt-input')),
      '以雨夜码头的悬疑氛围开场',
    );
    await tester
        .tap(find.byKey(const Key('assembly-opening-ai-generate-button')));
    await tester.pumpAndSettle();

    expect(ai.calls, 1);
    final args = ai.lastArgs!;
    expect(args['userPrompt'], '以雨夜码头的悬疑氛围开场');
    final worldview = args['worldview']! as String;
    expect(worldview, contains('幽暗森林'));
    expect(worldview, contains('终年不见天日的古老森林'));
    expect(args['protagonistName'], '莉安');
    expect(args['protagonistRole'], '主角');
    expect(args['protagonistPersonality'], '敏锐冷静');
    expect(args['protagonistBackground'], '来自北境的荒野猎手');

    final characters = args['selectedCharacters']! as List<Map<String, String>>;
    expect(characters.length, 2);
    expect(characters[1]['name'], '凯尔');
    expect(characters[1]['role'], '同伴');
    expect(characters[1]['personality'], '憨直忠诚');

    final relationships =
        args['characterRelationships']! as List<Map<String, String>>;
    expect(relationships.single['sourceName'], '莉安');
    expect(relationships.single['targetName'], '凯尔');
    expect(relationships.single['relationType'], '同伴');

    final npcs = args['npcs']! as List<Map<String, String>>;
    expect(npcs.single['name'], '老约克');
    expect(npcs.single['role'], '酒馆老板');

    // 结果写回可编辑字段。
    expect(
      _textOf(tester, const Key('assembly-opening-scene-input')),
      contains('莉安在废弃码头的阴影中睁开了眼'),
    );
    expect(_textOf(tester, const Key('assembly-option-1-input')), '调查四周的脚印');
    expect(_textOf(tester, const Key('assembly-option-2-input')), '呼唤同伴凯尔');
    expect(_textOf(tester, const Key('assembly-option-3-input')), '立即离开码头');
  });

  testWidgets('the same panel regenerates on demand', (tester) async {
    final ai = await pumpAssembly(tester);
    ai.nextResult = {
      'scene': '第一版序章',
      'options': '1 甲分支\n2 乙分支',
    };

    await tester
        .tap(find.byKey(const Key('assembly-opening-ai-generate-button')));
    await tester.pumpAndSettle();
    expect(ai.calls, 1);
    expect(find.text('重新生成'), findsOneWidget);

    ai.nextResult = {
      'scene': '第二版序章',
      'options': '1 丙分支\n2 丁分支',
    };
    await tester
        .tap(find.byKey(const Key('assembly-opening-ai-generate-button')));
    await tester.pumpAndSettle();

    expect(ai.calls, 2);
    expect(_textOf(tester, const Key('assembly-opening-scene-input')), '第二版序章');
    expect(_textOf(tester, const Key('assembly-option-1-input')), '丙分支');
  });

  testWidgets(
      'a failed generation surfaces the normalized error and never '
      'clears the content the user already has', (tester) async {
    final ai = await pumpAssembly(tester);

    await tester.enterText(
      find.byKey(const Key('assembly-opening-scene-input')),
      '用户已经写好的序章',
    );
    await tester.enterText(
      find.byKey(const Key('assembly-option-1-input')),
      '用户已经写好的分支',
    );
    await tester.pump();

    ai.nextError = '请求超时，请检查网络后重试';
    await tester
        .tap(find.byKey(const Key('assembly-opening-ai-generate-button')));
    await tester.pumpAndSettle();

    expect(ai.calls, 1);
    expect(
      find.byKey(const Key('assembly-opening-ai-error')),
      findsOneWidget,
    );
    expect(find.text('请求超时，请检查网络后重试'), findsOneWidget);
    // 生成失败绝不能清空用户已有内容。
    expect(
      _textOf(tester, const Key('assembly-opening-scene-input')),
      '用户已经写好的序章',
    );
    expect(
      _textOf(tester, const Key('assembly-option-1-input')),
      '用户已经写好的分支',
    );
  });
}
