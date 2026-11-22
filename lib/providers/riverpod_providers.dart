/// 应用唯一的运行时依赖注入入口。
///
/// 使用 Riverpod ChangeNotifierProvider (legacy) 包装现有 5 个
/// ChangeNotifier Provider，无需重写为 Notifier<T> 不可变状态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../services/database_service.dart';
import '../domain/setting_cards/setting_card_repository.dart';
import '../services/repositories/setting_card_repository_impl.dart';
import '../application/setting_cards/setting_card_service.dart';
import '../application/setting_cards/setting_card_library_runtime.dart';
import '../application/setting_cards/setting_card_adventure_snapshot.dart';
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
import '../core/localization/app_locale_controller.dart';
import '../core/refresh/page_refresh_controller.dart';

import '../application/llm/llm_gateway.dart';
import '../application/resource_library/character_relationship_management.dart';
import '../services/repositories/character_relationship_repository.dart';
import '../application/llm/ai_generator_llm_gateway.dart';
import '../services/ai_generator_service.dart';
import '../application/adventure/adventure_setup_use_case.dart';
import '../application/adventure/adventure_ai_use_case.dart';
import '../application/adventure/adventure_template_use_case.dart';
import '../features/adventure/application/use_cases/start_adventure_from_wizard.dart';
import '../controllers/adventure_setup_controller.dart';
import '../controllers/adventure_ai_controller.dart';
import '../controllers/adventure_template_controller.dart';
import '../controllers/adventure_game_controller.dart';
import '../services/ai_import_service.dart';
import '../services/read_aloud/read_aloud_controller.dart';

import '../services/read_aloud/flutter_tts_engine.dart';
import '../services/read_aloud/read_aloud_settings_store.dart';
import '../services/read_aloud/routed_read_aloud_engine.dart';
import '../application/conversation/export_conversation_use_case.dart';
import '../application/adventure/adventure_readiness_gate.dart';
import '../application/resources/authorized_generation_budget.dart';
import '../application/resources/legacy_tombstone_store.dart';
import '../features/resource_library/application/use_cases/resource_library_runtime.dart';
import '../features/resource_library/application/use_cases/tracked_state_library_runtime.dart';

// ═══════════════════════════════════════════════════════════════
// Repository Providers
// ═══════════════════════════════════════════════════════════════

final characterRelationshipManagementProvider =
    Provider<CharacterRelationshipManagement>((ref) {
  return CharacterRelationshipManagement(
    CharacterRelationshipRepositoryImpl(
      getDb: () => DatabaseService.database,
    ),
  );
});

final adventureRepoProvider = Provider<IAdventureRepository>((ref) {
  return AdventureRepositoryImpl(
    getDb: () => DatabaseService.database,
    tombstoneStore: ref.read(legacyTombstoneStoreProvider),
  );
});

final worldEntryRepoProvider = Provider<IWorldEntryRepository>((ref) {
  return WorldEntryRepositoryImpl(getDb: () => DatabaseService.database);
});

final libraryRepoProvider = Provider<ILibraryRepository>((ref) {
  return LibraryRepositoryImpl(
    getDb: () => DatabaseService.database,
    // The library deletes legacy rows through this chain, so it must carry the
    // tombstone store; without it `_moveToTrash` fail-closes.
    tombstoneStore: ref.read(legacyTombstoneStoreProvider),
  );
});

final settingsRepoProvider = Provider<ISettingsRepository>((ref) {
  return SettingsRepositoryImpl(getDb: () => DatabaseService.database);
});

/// Legacy-row tombstones shared with [DatabaseService]'s library singleton.
final legacyTombstoneStoreProvider = Provider<LegacyTombstoneStore>((ref) {
  return DatabaseService.legacyTombstoneStore;
});

// ═══════════════════════════════════════════════════════════════
// Core Provider — ChatProvider (Facade)
// ═══════════════════════════════════════════════════════════════

/// 全局朗读 Authority — 对话、资料库、组装预览与连续阅读共享同一个朗读
/// 会话与播放状态。
///
/// 独立于 ChatProvider 构建：朗读 UI 只需要 settings 仓库，不应因为渲染一个
/// 朗读按钮就拉起整个聊天运行时。阅读只使用轻量系统 TTS 后端。
final readAloudControllerProvider =
    ChangeNotifierProvider<ReadAloudController>((ref) {
  return ReadAloudController(
    engine: RoutedReadAloudEngine(systemEngine: createDefaultReadAloudEngine()),
    store: SettingsRepoReadAloudStore(ref.watch(settingsRepoProvider)),
  );
});

/// 全局 UI Locale 唯一 Authority。
final appLocaleControllerProvider =
    ChangeNotifierProvider<AppLocaleController>((ref) {
  return AppLocaleController(
    settingsRepo: ref.watch(settingsRepoProvider),
    readAloudController: ref.read(readAloudControllerProvider),
  );
});

/// ChatProvider 门面 — 持有 4 个子 Provider，所有跨模块 API 入口。
final ChangeNotifierProvider<ChatProvider> chatProvider =
    ChangeNotifierProvider<ChatProvider>((ref) {
  return ChatProvider.withRepos(
    adventureRepo: ref.watch(adventureRepoProvider),
    worldEntryRepo: ref.watch(worldEntryRepoProvider),
    libraryRepo: ref.watch(libraryRepoProvider),
    settingsRepo: ref.watch(settingsRepoProvider),
    // 朗读 Authority 由独立 Provider 持有，这里只注入以免出现第二套实现。
    // 必须用 read 而不是 watch：朗读状态每次变化（播放/暂停/进度）都会
    // notifyListeners，watch 会让整个 ChatProvider 被重建并释放旧子 Provider。
    readAloud: ref.read(readAloudControllerProvider),
    // Phase 10: Adventure 创建前必须经过 assembly readiness 门禁。
    readinessGate: ref.watch(adventureReadinessGateProvider),
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
    // Phase 5c: legacy writes go straight to the library repository and are
    // mirrored into the lightweight card the library reads.
    cardMirror: LegacyCardMirror(
      repository: ref.watch(settingCardRepositoryProvider),
    ),
    // Lets a re-edited AI-generated resource validate against its frozen
    // authorized budget instead of the ordinary absolute capacity.
    authorizedBudget: AuthorizedGenerationBudgetReader(
      getDb: () => DatabaseService.database,
    ),
    onLibraryChanged: () async {
      if (ref.exists(libraryProvider)) {
        await ref.read(libraryProvider).loadCharacterCards();
      }
      if (ref.exists(adventureProvider)) {
        await ref.read(adventureProvider).worldMgr.loadWorldviewPresets();
      }
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
    useCase: AdventureSetupUseCase(
      ref.read(libraryRepoProvider),
      // Phase 5c: the wizard must also see cards written by the card library
      // and AI drafts, which no longer land in the legacy tables.
      cards: ref.watch(settingCardRepositoryProvider),
    ),
  );
});

/// Adventure Wizard 的启动编排：持久化世界观/角色、重建快照、
/// 装配配置并通过 readiness gate。Screen 只负责输入、反馈与导航。
final startAdventureFromWizardUseCaseProvider =
    Provider<StartAdventureFromWizardUseCase>((ref) {
  return StartAdventureFromWizardUseCase(
    crud: ref.read(resourceCrudControllerProvider),
    setup: ref.read(adventureSetupControllerProvider),
    gate: ref.read(adventureReadinessGateProvider),
    cards: ref.watch(settingCardRepositoryProvider),
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

final adventureGameControllerProvider =
    Provider<AdventureGameController>((ref) {
  final adventure = ref.read(adventureProvider);
  return AdventureGameController(
    inventory: adventure.gameEngine.inventoryMgr,
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

/// Lightweight setting card store (single document per worldview/character/NPC).
final settingCardRepositoryProvider = Provider<SettingCardRepository>((ref) {
  return SettingCardRepositoryImpl(getDb: () => DatabaseService.database);
});

final settingCardServiceProvider = Provider<SettingCardService>((ref) {
  return SettingCardService(
    repository: ref.watch(settingCardRepositoryProvider),
    gateway: ref.watch(llmGatewayProvider),
  );
});

/// Library runtime: lightweight cards only (Phase 5c retired the legacy
/// fallback / Studio-backed library).
final resourceLibraryRuntimeProvider = Provider<ResourceLibraryRuntime>((ref) {
  return SettingCardLibraryRuntime(
    service: ref.watch(settingCardServiceProvider),
  );
});

/// Read-only projection source for the Resource Library「检测项目」surface.
///
/// It flattens the monitoring definitions already stored on character / NPC
/// resources through the existing library repository. It has no persistence of
/// its own and never reads adventure runtime state.
final trackedStateLibraryRuntimeProvider =
    Provider<TrackedStateLibraryRuntime>((ref) {
  return ProductionTrackedStateLibraryRuntime(
    repository: ref.watch(libraryRepoProvider),
    // Card-backed owners live in setting_cards, not the legacy library tables.
    cards: ref.watch(settingCardRepositoryProvider),
  );
});

/// Adventure 启动边界（Phase 10）：按被选资源解析 readiness，fail-closed
/// 阻止未就绪启动，并把被采用的 revision 冻结进 AdventureConfig。
final adventureReadinessGateProvider = Provider<IAdventureReadinessGate>((ref) {
  return SettingCardAwareReadinessGate(
    cards: ref.watch(settingCardRepositoryProvider),
  );
});
