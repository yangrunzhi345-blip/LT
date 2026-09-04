/// 应用唯一的运行时依赖注入入口。
///
/// 使用 Riverpod ChangeNotifierProvider (legacy) 包装现有 5 个
/// ChangeNotifier Provider，无需重写为 Notifier<T> 不可变状态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../services/database_service.dart';
import '../services/repositories/adventure_repository.dart';
import '../services/repositories/adventure_repository_impl.dart';
import '../services/repositories/world_entry_repository.dart';
import '../services/repositories/world_entry_repository_impl.dart';
import '../services/repositories/library_repository.dart';
import '../services/repositories/library_repository_impl.dart';
import '../services/repositories/settings_repository.dart';
import '../services/repositories/settings_repository_impl.dart';

import 'chat_provider.dart';
import 'settings_provider.dart';
import 'adventure_provider.dart';
import 'library_provider.dart';
import 'messaging_provider.dart';

import '../controllers/model_settings_controller.dart';
import '../controllers/resource_crud_controller.dart';
import '../core/refresh/page_refresh_controller.dart';

import '../application/llm/llm_gateway.dart';
import '../application/llm/ai_generator_llm_gateway.dart';
import '../services/ai_generator_service.dart';
import '../application/adventure/adventure_setup_use_case.dart';
import '../application/adventure/adventure_ai_use_case.dart';
import '../application/adventure/adventure_template_use_case.dart';
import '../application/adventure/map_generation_use_case.dart';
import '../controllers/adventure_setup_controller.dart';
import '../controllers/adventure_ai_controller.dart';
import '../controllers/adventure_template_controller.dart';
import '../controllers/adventure_game_controller.dart';
import '../controllers/scene_approval_controller.dart';
import '../controllers/resource_library_import_controller.dart';
import '../controllers/scene_batch_import_controller.dart';
import '../controllers/resource_card_import_controller.dart';
import '../application/resource_library/import_use_cases.dart';
import '../services/ai_import_service.dart';
import '../application/conversation/export_conversation_use_case.dart';

// ═══════════════════════════════════════════════════════════════
// Repository Providers
// ═══════════════════════════════════════════════════════════════

final adventureRepoProvider = Provider<IAdventureRepository>((ref) {
  return AdventureRepositoryImpl(getDb: () => DatabaseService.database);
});

final worldEntryRepoProvider = Provider<IWorldEntryRepository>((ref) {
  return WorldEntryRepositoryImpl(getDb: () => DatabaseService.database);
});

final libraryRepoProvider = Provider<ILibraryRepository>((ref) {
  return LibraryRepositoryImpl(getDb: () => DatabaseService.database);
});

final settingsRepoProvider = Provider<ISettingsRepository>((ref) {
  return SettingsRepositoryImpl(getDb: () => DatabaseService.database);
});

// ═══════════════════════════════════════════════════════════════
// Core Provider — ChatProvider (Facade)
// ═══════════════════════════════════════════════════════════════

/// ChatProvider 门面 — 持有 4 个子 Provider，所有跨模块 API 入口。
final chatProvider = ChangeNotifierProvider<ChatProvider>((ref) {
  return ChatProvider.withRepos(
    adventureRepo: ref.watch(adventureRepoProvider),
    worldEntryRepo: ref.watch(worldEntryRepoProvider),
    libraryRepo: ref.watch(libraryRepoProvider),
    settingsRepo: ref.watch(settingsRepoProvider),
  );
});

// ═══════════════════════════════════════════════════════════════
// Sub-Providers — 从 ChatProvider 提取，各自独立响应变更
// ═══════════════════════════════════════════════════════════════

/// SettingsProvider — API 配置 / 模型 / 主题 / TTS / 翻译
final settingsProvider = ChangeNotifierProvider<SettingsProvider>((ref) {
  return ref.watch(chatProvider).settingsProvider;
}, disposeNotifier: false);

/// AdventureProvider — 冒险 CRUD / 消息 / 游戏状态 / 世界条目 / 分支
final adventureProvider = ChangeNotifierProvider<AdventureProvider>((ref) {
  return ref.watch(chatProvider).adventureProvider;
}, disposeNotifier: false);

/// LibraryProvider — 角色卡 / 提示词预设 / 人格化身
final libraryProvider = ChangeNotifierProvider<LibraryProvider>((ref) {
  return ref.watch(chatProvider).libraryProvider;
}, disposeNotifier: false);

/// MessagingProvider — 聊天引擎 / Token / 搜索 / 书签 (实现 ChatEngineHost)
final messagingProvider = ChangeNotifierProvider<MessagingProvider>((ref) {
  return ref.watch(chatProvider).messagingProvider;
}, disposeNotifier: false);

// ═══════════════════════════════════════════════════════════════
// Controllers & Gateways
// ═══════════════════════════════════════════════════════════════

final llmGatewayProvider = Provider<LlmGateway>((ref) {
  return AiGeneratorLlmGateway(
    () => AiGeneratorService(ref.read(chatProvider).llmService),
    isConfiguredResolver: () =>
        ref.read(chatProvider).llmService.config.apiKey.trim().isNotEmpty,
    llmResolver: () => ref.read(chatProvider).llmService,
  );
});

final resourceCrudControllerProvider =
    ChangeNotifierProvider<ResourceCrudController>((ref) {
  return ResourceCrudController(
    repository: ref.read(libraryRepoProvider),
    onLibraryChanged: () {
      ref.read(libraryProvider).loadCharacterCards();
      ref.read(adventureProvider).worldMgr.loadWorldviewPresets();
    },
  );
});

final modelSettingsControllerProvider =
    ChangeNotifierProvider<ModelSettingsController>((ref) {
  return ModelSettingsController(
    llmResolver: () => ref.read(chatProvider).llmService,
  );
});

final pageRefreshControllerProvider = Provider<PageRefreshController>((ref) {
  final controller = PageRefreshController();
  ref.onDispose(controller.dispose);
  return controller;
});

final adventureSetupControllerProvider =
    ChangeNotifierProvider<AdventureSetupController>((ref) {
  return AdventureSetupController(
    useCase: AdventureSetupUseCase(ref.read(libraryRepoProvider)),
  );
});

final adventureAiControllerProvider =
    ChangeNotifierProvider<AdventureAiController>((ref) {
  return AdventureAiController(
    useCase: AdventureAiUseCase(ref.read(llmGatewayProvider)),
  );
});

final adventureTemplateControllerProvider =
    ChangeNotifierProvider<AdventureTemplateController>((ref) {
  return AdventureTemplateController(
    useCase: AdventureTemplateUseCase(ref.read(libraryRepoProvider)),
  );
});

final mapGenerationUseCaseProvider = Provider<MapGenerationUseCase>((ref) {
  return MapGenerationUseCase(ref.read(llmGatewayProvider));
});

final adventureGameControllerProvider =
    Provider<AdventureGameController>((ref) {
  final adventure = ref.read(adventureProvider);
  return AdventureGameController(
    inventory: adventure.gameEngine.inventoryMgr,
    mapService: adventure.narrativeMapService,
    mapGenUseCase: ref.read(mapGenerationUseCaseProvider),
    adventureRepo: ref.read(adventureRepoProvider),
  );
});

final sceneApprovalControllerProvider =
    ChangeNotifierProvider.autoDispose<SceneApprovalController>((ref) {
  return SceneApprovalController(chatProvider: () => ref.read(chatProvider));
});

final conversationCharacterImportUseCaseProvider =
    Provider<ImportConversationCharacterUseCase>((ref) {
  return ImportConversationCharacterUseCase(
    gateway: ref.read(llmGatewayProvider),
    repository: ref.read(libraryRepoProvider),
  );
});

final worldviewImportUseCaseProvider = Provider<ImportWorldviewUseCase>((ref) {
  return ImportWorldviewUseCase(
    gateway: ref.read(llmGatewayProvider),
    repository: ref.read(libraryRepoProvider),
  );
});

final resourceLibraryImportControllerProvider =
    ChangeNotifierProvider<ResourceLibraryImportController>((ref) {
  return ResourceLibraryImportController(
    conversationCharacterUseCase:
        ref.read(conversationCharacterImportUseCaseProvider),
    worldviewUseCase: ref.read(worldviewImportUseCaseProvider),
    onWorldviewSaved: () =>
        ref.read(adventureProvider).worldMgr.loadWorldviewPresets(),
  );
});

final sceneBatchImportUseCaseProvider =
    Provider<SceneBatchImportUseCase>((ref) {
  return SceneBatchImportUseCase(
    gateway: ref.read(llmGatewayProvider),
    repository: ref.read(libraryRepoProvider),
  );
});

final sceneBatchImportControllerProvider =
    ChangeNotifierProvider<SceneBatchImportController>((ref) {
  return SceneBatchImportController(
    useCase: ref.read(sceneBatchImportUseCaseProvider),
  );
});

final resourceCardImportUseCaseProvider =
    Provider<ResourceCardImportUseCase>((ref) {
  return ResourceCardImportUseCase(
    gateway: ref.read(llmGatewayProvider),
    repository: ref.read(libraryRepoProvider),
  );
});

final resourceCardImportControllerProvider =
    ChangeNotifierProvider<ResourceCardImportController>((ref) {
  return ResourceCardImportController(
    useCase: ref.read(resourceCardImportUseCaseProvider),
  );
});

final aiImportServiceProvider = Provider<AiImportService>((ref) {
  final settings = ref.watch(settingsProvider);
  return AiImportService(settings.llmService);
});

final conversationExportUseCaseProvider =
    Provider<ConversationExportUseCase>((ref) {
  return const ConversationExportUseCase();
});

