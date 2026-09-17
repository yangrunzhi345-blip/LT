/// 应用唯一的运行时依赖注入入口。
///
/// 使用 Riverpod ChangeNotifierProvider (legacy) 包装现有 5 个
/// ChangeNotifier Provider，无需重写为 Notifier<T> 不可变状态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:sqflite/sqflite.dart';

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
import '../application/resources/compression_coordinator.dart';
import '../application/resources/compression_job_repository.dart';
import '../application/resources/compression_worker.dart';
import '../application/resources/part_content_commit_service.dart';
import '../application/resources/part_generation_coordinator.dart';
import '../application/resources/resource_autosave_repository.dart';
import '../application/resources/resource_autosave_service.dart';
import '../application/resources/resource_blueprint_repository.dart';
import '../application/resources/resource_capacity_repository.dart';
import '../application/resources/resource_capacity_service.dart';
import '../application/resources/resource_compression_publisher.dart';
import '../application/resources/resource_creation_pipeline.dart';
import '../application/resources/resource_generation_task_repository.dart';
import '../application/resources/resource_revision_repository.dart';
import '../application/resources/resource_revision_service.dart';
import '../application/resources/resource_trash_repository.dart';
import '../application/resources/resource_trash_service.dart';
import '../application/resources/section_control_service.dart';
import '../application/resources/streaming_generation_session_repository.dart';
import '../application/resources/streaming_resource_generation_service.dart';
import '../features/resource_library/application/use_cases/resource_trash_runtime.dart';
import '../features/resource_studio/application/use_cases/resource_capacity_runtime.dart';
import '../features/resource_studio/application/use_cases/resource_revision_runtime.dart';
import '../features/resource_studio/application/use_cases/resource_studio_runtime.dart';
import '../features/resource_studio/application/use_cases/section_control_runtime.dart';
import '../features/resource_studio/application/use_cases/streaming_section_regeneration_executor.dart';
import '../services/repositories/resource_tree_repository_impl.dart';
import '../services/repositories/section_control_repository_impl.dart';
import '../controllers/streaming_resource_generation_controller.dart';

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

/// The single revision repository of this process (Phase 9).
///
/// Shared instead of re-created per feature because revision ids are generated
/// from a timestamp plus a per-instance counter: two instances could collide
/// inside the same microsecond. One instance makes the generator single, which
/// is the same reason the compression coordinator is a singleton.
final resourceRevisionRepositoryProvider =
    Provider<IResourceRevisionRepository>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return ResourceRevisionRepositoryImpl(getDb: getDb);
});

/// The single revision capture engine of this process (Phase 9).
///
/// Every path that may lose confirmed content — generation commit, manual
/// edit, compression publish, restore, delete — goes through this one engine,
/// so the "record before, record after" rule has exactly one implementation.
final revisionCaptureEngineProvider = Provider<RevisionCaptureEngine>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return RevisionCaptureEngine(
    revisionRepository: ref.read(resourceRevisionRepositoryProvider),
    treeBoundary: ResourceTreeRepositoryImpl(getDb: getDb),
  );
});

/// Recycle-bin persistence (Phase 9).
final resourceTrashRepositoryProvider =
    Provider<IResourceTrashRepository>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return ResourceTrashRepositoryImpl(getDb: getDb);
});

/// Autosave draft journal (Phase 9).
final resourceAutosaveRepositoryProvider =
    Provider<IResourceAutosaveRepository>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return ResourceAutosaveRepositoryImpl(getDb: getDb);
});

/// The single writer of manual Part body changes (Phase 9).
///
/// Reused by both the autosave debounce and the explicit Studio save so an
/// editor flush and a button save cannot produce two different transactions for
/// the same content.
final partContentCommitServiceProvider =
    Provider<PartContentCommitService>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return PartContentCommitService(
    treeBoundary: ResourceTreeRepositoryImpl(getDb: getDb),
    validationBoundary: SectionControlRepositoryImpl(getDb: getDb),
    captureEngine: ref.read(revisionCaptureEngineProvider),
    autosaveRepository: ref.read(resourceAutosaveRepositoryProvider),
    getDb: getDb,
    taskReset: PartGenerationTaskRepositoryImpl(getDb: getDb),
  );
});

/// Revision history, restore and retention cleanup (Phase 9).
final resourceRevisionServiceProvider =
    Provider<ResourceRevisionService>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return ResourceRevisionService(
    revisionRepository: ref.read(resourceRevisionRepositoryProvider),
    captureEngine: ref.read(revisionCaptureEngineProvider),
    treeBoundary: ResourceTreeRepositoryImpl(getDb: getDb),
    getDb: getDb,
    taskReset: PartGenerationTaskRepositoryImpl(getDb: getDb),
  );
});

/// Recycle-bin operations (Phase 9).
final resourceTrashServiceProvider = Provider<ResourceTrashService>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return ResourceTrashService(
    repository: ref.read(resourceTrashRepositoryProvider),
    treeBoundary: ResourceTreeRepositoryImpl(getDb: getDb),
    captureEngine: ref.read(revisionCaptureEngineProvider),
    getDb: getDb,
  );
});

/// Factory for per-editor autosave services.
///
/// A factory rather than a cached provider because the service owns mutable
/// per-editor state (the debounce buffer). Two open editors must not share one
/// buffer, or closing one would flush the other's text.
final resourceAutosaveServiceFactoryProvider =
    Provider<AutosaveServiceFactory>((ref) {
  return () => ResourceAutosaveService(
        journal: ref.read(resourceAutosaveRepositoryProvider),
        committer: ref.read(partContentCommitServiceProvider),
        treeBoundary: ResourceTreeRepositoryImpl(
          getDb: () => DatabaseService.database,
        ),
        getDb: () => DatabaseService.database,
      );
});

/// Production runtime adapter used by the Resource Studio feature.
final resourceStudioRuntimeProvider = Provider<ResourceStudioRuntime>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  final treeRepository = ResourceTreeRepositoryImpl(getDb: getDb);
  final taskRepository = PartGenerationTaskRepositoryImpl(
    getDb: getDb,
    // Phase 9: the commit transaction now also records the pre-write state and
    // the post-write revision head, so a regeneration can always be rolled back.
    revisionBoundary: ref.read(revisionCaptureEngineProvider),
  );
  final blueprintRepository = ResourceBlueprintRepositoryImpl(
    getDb: getDb,
    treeRepository: treeRepository,
  );
  final pipeline = ResourceCreationPipeline(
    getDb: getDb,
    hasAiCredentials: () => ref.read(chatProvider).isKeyConfigured,
    treeRepository: treeRepository,
    blueprintRepository: blueprintRepository,
    generationTaskRepository: taskRepository,
    revisionCapture: ref.read(revisionCaptureEngineProvider),
  );
  final coordinator = PartGenerationCoordinator(
    taskRepository: taskRepository,
    blueprintRepository: blueprintRepository,
    pipeline: pipeline,
    gateway: ref.read(llmGatewayProvider),
    maxConcurrency: 1,
  );
  final sessionRepository = StreamingGenerationSessionRepositoryImpl(
    getDb: getDb,
  );
  final service = StreamingResourceGenerationService(
    sessionRepository: sessionRepository,
    taskRepository: taskRepository,
    blueprintRepository: blueprintRepository,
    coordinator: coordinator,
  );
  final runtime = StreamingResourceStudioRuntime(
    controller: StreamingResourceGenerationController(
      service: service,
      sessionRepository: sessionRepository,
    ),
    sessionRepository: sessionRepository,
    treeRepository: treeRepository,
    blueprintRepository: blueprintRepository,
    pipeline: pipeline,
    gateway: ref.read(llmGatewayProvider),
  );
  ref.onDispose(runtime.dispose);
  return runtime;
});

/// Production section-control runtime used by the Studio section controls.
///
/// Reuses the Studio runtime's streaming controller so regeneration shares one
/// generation service, one event stream and one set of Phase 5 tasks. This
/// provider requires the production Studio runtime; widget tests override it.
final sectionControlRuntimeProvider = Provider<SectionControlRuntime>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  final studioRuntime = ref.read(resourceStudioRuntimeProvider);
  if (studioRuntime is! StreamingResourceStudioRuntime) {
    throw StateError(
      'sectionControlRuntimeProvider 需要生产 StreamingResourceStudioRuntime；'
      '测试应覆盖本 provider 提供 fake runtime',
    );
  }

  final service = SectionControlService(
    repository: SectionControlRepositoryImpl(getDb: getDb),
    treeRepository: ResourceTreeRepositoryImpl(getDb: getDb),
    regenerationExecutor: StreamingSectionRegenerationExecutor(
      runtime: StreamingRegenerationRuntimeAdapter(
        controller: studioRuntime.controller,
        sessionRepository: studioRuntime.sessionRepository,
      ),
    ),
    partCommitService: ref.read(partContentCommitServiceProvider),
    trashService: ref.read(resourceTrashServiceProvider),
    revisionService: ref.read(resourceRevisionServiceProvider),
  );
  final runtime = SectionControlServiceRuntime(service: service);
  ref.onDispose(runtime.dispose);
  return runtime;
});

/// Production capacity measurement service.
///
/// Shared by the compression coordinator and the Studio runtime so both read
/// the same thresholds and the same measured numbers.
final resourceCapacityServiceProvider =
    Provider<ResourceCapacityService>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return ResourceCapacityService(
    repository: ResourceCapacityRepositoryImpl(getDb: getDb),
  );
});

/// Production revision runtime used by the Studio history panel (Phase 9).
final resourceRevisionRuntimeProvider =
    Provider<ResourceRevisionRuntime>((ref) {
  return ResourceRevisionServiceRuntime(
    service: ref.read(resourceRevisionServiceProvider),
  );
});

/// Production recycle-bin runtime used by the Resource Library (Phase 9).
final resourceTrashRuntimeProvider = Provider<ResourceTrashRuntime>((ref) {
  return ResourceTrashServiceRuntime(
    service: ref.read(resourceTrashServiceProvider),
  );
});

/// The single compression coordinator of this process.
///
/// One instance means one worker identity and one place that owns job claims;
/// it is deliberately not `autoDispose`, because the background worker outlives
/// any single Studio page.
final compressionCoordinatorProvider = Provider<CompressionCoordinator>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return CompressionCoordinator(
    jobRepository: CompressionJobRepositoryImpl(getDb: getDb),
    treeRepository: ResourceTreeRepositoryImpl(getDb: getDb),
    capacityRepository: ResourceCapacityRepositoryImpl(getDb: getDb),
    llmPort: LlmGatewayCompressionAdapter(ref.read(llmGatewayProvider)),
  );
});

/// Phase 8's background compression worker.
///
/// Started once at app startup (it reclaims jobs orphaned by a previous
/// process) and triggered when an editor is left. It is the runtime owner of
/// the automatic compression path, so that path is not tied to a screen.
final compressionBackgroundWorkerProvider =
    Provider<CompressionBackgroundWorker>((ref) {
  return CompressionBackgroundWorker(
    coordinator: ref.read(compressionCoordinatorProvider),
    capacityService: ref.read(resourceCapacityServiceProvider),
  );
});

/// Publishes validated compression candidates behind the revision boundary.
///
/// The Phase 8 coordinator only ever creates candidates; this is the single
/// path that turns one into the resource head, and it always records the
/// pre-compression content as a revision first.
final compressionPublisherProvider = Provider<CompressionPublisher>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return CompressionPublisher(
    jobRepository: CompressionJobRepositoryImpl(getDb: getDb),
    revisionService: ref.read(resourceRevisionServiceProvider),
    getDb: getDb,
  );
});

/// Production capacity runtime used by the Studio capacity panel.
///
/// Composes the measured capacity service with the compression coordinator so
/// the panel can show live capacity and queue compression candidates. The
/// coordinator only ever writes candidates; publishing goes through
/// [compressionPublisherProvider], which is revision-boundary protected.
final resourceCapacityRuntimeProvider =
    Provider<ResourceCapacityRuntime>((ref) {
  return ResourceCapacityServiceRuntime(
    capacityService: ref.read(resourceCapacityServiceProvider),
    compressionCoordinator: ref.read(compressionCoordinatorProvider),
    compressionPublisher: ref.read(compressionPublisherProvider),
    worker: ref.read(compressionBackgroundWorkerProvider),
  );
});
