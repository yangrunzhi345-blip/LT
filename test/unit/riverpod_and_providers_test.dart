import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/models/app_section.dart';
import 'package:lt_dialogue/models/character_card.dart';
import 'package:lt_dialogue/models/llm_provider.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/controllers/model_settings_controller.dart';
import 'package:lt_dialogue/application/llm/model_settings_use_case.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_provider_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();

    container = ProviderContainer();
  });

  tearDown(() async {
    await Future.delayed(const Duration(milliseconds: 150));
    container.dispose();
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Phase 4: Riverpod & Providers Verification', () {
    test('ProviderContainer resolves all core providers without UI', () {
      final chat = container.read(chatProvider);
      expect(chat, isNotNull);

      final settings = container.read(settingsProvider);
      expect(settings, isNotNull);
      expect(identical(chat.settingsProvider, settings), isTrue);

      final adventure = container.read(adventureProvider);
      expect(adventure, isNotNull);
      expect(identical(chat.adventureProvider, adventure), isTrue);

      final library = container.read(libraryProvider);
      expect(library, isNotNull);
      expect(identical(chat.libraryProvider, library), isTrue);

      final messaging = container.read(messagingProvider);
      expect(messaging, isNotNull);
      expect(identical(chat.messagingProvider, messaging), isTrue);

      final crudController = container.read(resourceCrudControllerProvider);
      expect(crudController, isNotNull);

      final modelSettings = container.read(modelSettingsControllerProvider);
      expect(modelSettings, isNotNull);

      final refresh = container.read(pageRefreshControllerProvider);
      expect(refresh, isNotNull);
    });

    test('SettingsProvider updates API key and provider type', () async {
      final settings = container.read(settingsProvider);

      expect(settings.worldviewDeepThinkingGeneration, isFalse);
      expect(settings.characterCardDeepThinkingGeneration, isFalse);
      await settings.setWorldviewDeepThinkingGeneration(true);
      await settings.setCharacterCardDeepThinkingGeneration(true);
      expect(settings.worldviewDeepThinkingGeneration, isTrue);
      expect(settings.characterCardDeepThinkingGeneration, isTrue);
      final settingsRepo = container.read(settingsRepoProvider);
      expect(
        await settingsRepo.getSetting('worldview_deep_thinking_generation'),
        '1',
      );
      expect(
        await settingsRepo
            .getSetting('character_card_deep_thinking_generation'),
        '1',
      );

      await settings.setApiKey('sk-test-key-12345');
      expect(settings.apiKey, equals('sk-test-key-12345'));
      expect(settings.isKeyConfigured, isTrue);

      await settings.setProviderType(LLMProvider.custom);
      expect(settings.providerType, equals(LLMProvider.custom));
      expect(settings.modelName, equals(LLMProvider.custom.defaultModel));
    });

    test('LibraryProvider saves CharacterCard to DB and memory list', () async {
      final library = container.read(libraryProvider);

      final card = CharacterCard(
        name: '艾丽卡',
        description: '帝国边境的游侠',
        personality: '冷静、敏锐',
      );

      await library.saveCharacterCard(card);
      await library.loadCharacterCards();

      expect(library.savedCharacterCards.any((c) => c.name == '艾丽卡'), isTrue);
    });

    test('ModelSettingsController manages configuration state and test flow',
        () async {
      final controller = ModelSettingsController(
        llmResolver: () => container.read(chatProvider).llmService,
        useCase: ModelSettingsUseCase(
          configurationTester: (config) async => true,
        ),
      );

      controller.setProvider(LLMProvider.deepseek);
      controller.setModel('deepseek-v4-flash');
      expect(controller.currentProvider, equals(LLMProvider.deepseek));
      expect(controller.currentModel, equals('deepseek-v4-flash'));

      final success = await controller.testConnection(
        provider: LLMProvider.deepseek,
        apiKey: 'fake-key',
        model: 'deepseek-v4-flash',
      );

      expect(success, isTrue);
      expect(controller.testResult, equals('连接成功'));
      expect(controller.testing, isFalse);

      controller.dispose();
    });

    test(
        'ChatProvider switches section and protects concurrency on sendMessage',
        () async {
      final chat = container.read(chatProvider);

      expect(chat.currentSection, equals(AppSection.home));
      chat.setCurrentSection(AppSection.adventure);
      expect(chat.currentSection, equals(AppSection.adventure));
      chat.setCurrentSection(AppSection.resources);
      expect(chat.currentSection, equals(AppSection.resources));
      chat.setCurrentSection(AppSection.settings);
      expect(chat.currentSection, equals(AppSection.settings));

      // Test concurrency / empty check
      final msgCountBefore = chat.messages.length;
      await chat.sendMessage('');
      expect(chat.messages.length, equals(msgCountBefore));

      // With unconfigured API key, sendMessage blocks and displays warning message
      await chat.sendMessage('你好');
      expect(
          chat.messages.any((m) => m.content.contains('请先配置 API 密钥')), isTrue);
    });

    test('ChatProvider defaults sidebar to collapsed and toggles correctly',
        () async {
      final chat = container.read(chatProvider);

      // Default state is collapsed (false)
      expect(chat.isMainSidebarExpanded, isFalse);

      // Toggle to expanded
      chat.toggleMainSidebarExpanded();
      expect(chat.isMainSidebarExpanded, isTrue);

      // Toggle back to collapsed
      chat.toggleMainSidebarExpanded();
      expect(chat.isMainSidebarExpanded, isFalse);
    });
  });
}
