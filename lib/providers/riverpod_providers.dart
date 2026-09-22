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
import '../core/localization/app_locale_controller.dart';
import '../core/refresh/page_refresh_controller.dart';

import '../application/llm/llm_gateway.dart';
import '../application/llm/ai_generator_llm_gateway.dart';
import '../services/ai_generator_service.dart';
import '../application/adventure/adventure_setup_use_case.dart';
import '../application/adventure/adventure_ai_use_case.dart';
import '../application/adventure/adventure_template_use_case.dart';
import '../controllers/adventure_setup_controller.dart';
import '../controllers/adventure_ai_controller.dart';
import '../controllers/adventure_template_controller.dart';
import '../controllers/adventure_game_controller.dart';
import '../controllers/resource_library_import_controller.dart';
import '../controllers/scene_batch_import_controller.dart';
import '../controllers/resource_card_import_controller.dart';
import '../application/resource_library/import_use_cases.dart';
import '../services/ai_import_service.dart';
import '../services/read_aloud/flutter_tts_engine.dart';
import '../services/read_aloud/read_aloud_controller.dart';
import '../services/read_aloud/read_aloud_settings_store.dart';
import '../application/conversation/export_conversation_use_case.dart';
import '../application/resources/compression_coordinator.dart';
import '../application/resources/compression_job_repository.dart';
import '../application/resources/compression_worker.dart';
import '../application/resources/legacy_library_row_purger.dart';
import '../application/resources/resource_owned_state_purger.dart';
import '../application/resources/assembly_readiness_coordinator.dart';
import '../application/resources/assembly_readiness_repository.dart';
import '../application/resources/resource_assembly_builder.dart';
import '../application/adventure/adventure_readiness_gate.dart';
import '../application/resources/part_content_commit_service.dart';
import '../application/resources/part_generation_coordinator.dart';
import '../application/resources/resource_autosave_repository.dart';
import '../application/resources/resource_autosave_service.dart';
import '../application/resources/resource_blueprint_repository.dart';
import '../application/resources/resource_capacity_repository.dart';
import '../application/resources/resource_capacity_service.dart';
import '../application/resources/resource_compression_publisher.dart';
import '../application/resources/legacy_creation_bridge.dart';
import '../application/resources/resource_creation_pipeline.dart';
import '../application/resources/resource_generation_task_repository.dart';
import '../application/resources/resource_library_trash_bridge.dart';
import '../application/resources/resource_revision_maintenance.dart';
import '../application/resources/resource_revision_repository.dart';
import '../application/resources/resource_revision_service.dart';
import '../application/resources/resource_trash_repository.dart';
import '../application/resources/resource_trash_service.dart';
import '../application/resources/section_control_service.dart';
import '../application/resources/streaming_generation_session_repository.dart';
import '../application/resources/streaming_resource_generation_service.dart';
import '../features/resource_library/application/use_cases/resource_trash_runtime.dart';
import '../features/resource_library/application/use_cases/resource_library_runtime.dart';
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
  return LibraryRepositoryImpl(
    getDb: () => DatabaseService.database,
    // Phase 9 (R2-B1): the Resource Library UI deletes through this chain, so
    // it must carry the recycle-bin bridge. Without it `_moveToTrash`
    // fail-closes and every delete in the UI fails.
    trashBridge: ref.read(resourceLibraryTrashBridgeProvider),
  );
});

final settingsRepoProvider = Provider<ISettingsRepository>((ref) {
  return SettingsRepositoryImpl(getDb: () => DatabaseService.database);
});

// ═══════════════════════════════════════════════════════════════
// Core Provider — ChatProvider (Facade)
// ═══════════════════════════════════════════════════════════════

/// 全局朗读 Authority — 对话、资料库、Resource Studio、组装预览与连续阅读
/// 共享同一个朗读会话与播放状态。
///
/// 独立于 ChatProvider 构建：朗读 UI 只需要 settings 仓库，不应因为渲染一个
/// 朗读按钮就拉起整个聊天运行时。
final readAloudControllerProvider =
    ChangeNotifierProvider<ReadAloudController>((ref) {
  // ChangeNotifierProvider 自己负责 dispose notifier，不要再挂 onDispose，
  // 否则会二次 dispose 同一控制器。
  return ReadAloudController(
    engine: createDefaultReadAloudEngine(),
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
final chatProvider = ChangeNotifierProvider<ChatProvider>((ref) {
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

/// The single production creation pipeline of the process.
///
/// Built by the streaming-generation infrastructure so Library CRUD, imports
/// and Studio creation share one pipeline contract including revision capture
/// (R05-B). Do not construct ad-hoc pipelines elsewhere.
final resourceCreationPipelineProvider =
    Provider<ResourceCreationPipeline>((ref) {
  return ref.read(_streamingGenerationInfrastructureProvider).pipeline;
});

/// The production creation bridge over [resourceCreationPipelineProvider].
final legacyCreationBridgeProvider = Provider<LegacyCreationBridge>((ref) {
  return LegacyCreationBridge(ref.read(resourceCreationPipelineProvider));
});

final resourceCrudControllerProvider =
    ChangeNotifierProvider<ResourceCrudController>((ref) {
  return ResourceCrudController(
    repository: ref.read(libraryRepoProvider),
    creationPipeline: ref.read(resourceCreationPipelineProvider),
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

final adventureGameControllerProvider =
    Provider<AdventureGameController>((ref) {
  final adventure = ref.read(adventureProvider);
  return AdventureGameController(
    inventory: adventure.gameEngine.inventoryMgr,
  );
});

final conversationCharacterImportUseCaseProvider =
    Provider<ImportConversationCharacterUseCase>((ref) {
  return ImportConversationCharacterUseCase(
    gateway: ref.read(llmGatewayProvider),
    bridge: ref.read(legacyCreationBridgeProvider),
  );
});

final worldviewImportUseCaseProvider = Provider<ImportWorldviewUseCase>((ref) {
  return ImportWorldviewUseCase(
    gateway: ref.read(llmGatewayProvider),
    bridge: ref.read(legacyCreationBridgeProvider),
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
    bridge: ref.read(legacyCreationBridgeProvider),
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
    bridge: ref.read(legacyCreationBridgeProvider),
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
///
/// [legacyRowPort] is what makes the bin's *explicit* permanent delete the only
/// code path able to remove a legacy library row; normal deletes go through
/// [resourceLibraryTrashBridgeProvider] instead.
final resourceTrashServiceProvider = Provider<ResourceTrashService>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  return ResourceTrashService(
    repository: ref.read(resourceTrashRepositoryProvider),
    treeBoundary: ResourceTreeRepositoryImpl(getDb: getDb),
    captureEngine: ref.read(revisionCaptureEngineProvider),
    getDb: getDb,
    legacyRowPort: LegacyLibraryRowPurger(getDb: getDb),
    // R03-B: auxiliary state is discharged inside the purge transaction.
    ownedStatePort: ResourceOwnedStatePurger(),
  );
});

/// Runs the revision retention pass at a controlled point (Phase 9).
///
/// Started once from `main.dart`'s post-frame hook: without a production trigger
/// the revision chain grew forever (audit P9-M3).
final revisionMaintenanceProvider =
    Provider<ResourceRevisionMaintenance>((ref) {
  return ResourceRevisionMaintenance(
    revisionService: ref.read(resourceRevisionServiceProvider),
  );
});

/// Routes Resource Library deletes into the recycle bin (Phase 9).
///
/// Deliberately delegates to [DatabaseService.libraryTrashBridge] instead of
/// building its own: that static is the single bridge source, so this chain
/// and `DatabaseService._libraryRepo` can never drift into one-wired /
/// one-unwired assemblies again (R2-B1).
final resourceLibraryTrashBridgeProvider =
    Provider<ResourceLibraryTrashBridge>((ref) {
  return DatabaseService.libraryTrashBridge;
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

final class _StreamingGenerationInfrastructure {
  const _StreamingGenerationInfrastructure({
    required this.treeRepository,
    required this.taskRepository,
    required this.blueprintRepository,
    required this.pipeline,
    required this.coordinator,
  });

  final ResourceTreeRepositoryImpl treeRepository;
  final PartGenerationTaskRepositoryImpl taskRepository;
  final ResourceBlueprintRepositoryImpl blueprintRepository;
  final ResourceCreationPipeline pipeline;
  final PartGenerationCoordinator coordinator;
}

final _streamingGenerationInfrastructureProvider =
    Provider<_StreamingGenerationInfrastructure>((ref) {
  Future<Database> getDb() => DatabaseService.database;
  final readinessCoordinator = ref.read(assemblyReadinessCoordinatorProvider);
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
    revisionCapture: ref.read(revisionCaptureEngineProvider),
  );
  final pipeline = ResourceCreationPipeline(
    getDb: getDb,
    hasAiCredentials: () => ref.read(chatProvider).isKeyConfigured,
    onResourceReadyForAssembly: (resourceId) async {
      await readinessCoordinator.prepare(resourceId);
    },
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
  return _StreamingGenerationInfrastructure(
    treeRepository: treeRepository,
    taskRepository: taskRepository,
    blueprintRepository: blueprintRepository,
    pipeline: pipeline,
    coordinator: coordinator,
  );
});

final streamingGenerationSessionRepositoryProvider =
    Provider<IStreamingGenerationSessionRepository>((ref) {
  return StreamingGenerationSessionRepositoryImpl(
    getDb: () => DatabaseService.database,
  );
});

final streamingResourceGenerationServiceProvider =
    Provider<StreamingResourceGenerationService>((ref) {
  final infrastructure = ref.read(_streamingGenerationInfrastructureProvider);
  final service = StreamingResourceGenerationService(
    sessionRepository: ref.read(streamingGenerationSessionRepositoryProvider),
    taskRepository: infrastructure.taskRepository,
    blueprintRepository: infrastructure.blueprintRepository,
    coordinator: infrastructure.coordinator,
    onGenerationCompletedForAssembly: (resourceId) async {
      await ref.read(assemblyReadinessCoordinatorProvider).prepare(resourceId);
    },
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Recovers persisted in-flight sessions without replaying model requests.
final streamingGenerationRecoveryProvider = FutureProvider<void>((ref) async {
  final repository = ref.read(streamingGenerationSessionRepositoryProvider);
  final service = ref.read(streamingResourceGenerationServiceProvider);
  final interrupted = await repository.findInterruptedSessions();
  Object? firstError;
  StackTrace? firstStackTrace;

  for (final session in interrupted) {
    try {
      await service.recoverInterruptedGeneration(
        session.sessionId,
        autoResume: false,
      );
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  if (firstError case final error?) {
    Error.throwWithStackTrace(error, firstStackTrace!);
  }
});

/// Production runtime adapter used by the Resource Studio feature.
final resourceStudioRuntimeProvider = Provider<ResourceStudioRuntime>((ref) {
  final infrastructure = ref.read(_streamingGenerationInfrastructureProvider);
  final sessionRepository =
      ref.read(streamingGenerationSessionRepositoryProvider);
  final service = ref.read(streamingResourceGenerationServiceProvider);
  final runtime = StreamingResourceStudioRuntime(
    controller: StreamingResourceGenerationController(
      service: service,
      sessionRepository: sessionRepository,
      ownsService: false,
    ),
    sessionRepository: sessionRepository,
    treeRepository: infrastructure.treeRepository,
    blueprintRepository: infrastructure.blueprintRepository,
    pipeline: infrastructure.pipeline,
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

/// Production data and creation boundary for the unified Resource Library.
final resourceLibraryRuntimeProvider = Provider<ResourceLibraryRuntime>((ref) {
  return ProductionResourceLibraryRuntime(
    crud: ref.read(resourceCrudControllerProvider),
    studio: ref.read(resourceStudioRuntimeProvider),
    readiness: ref.read(assemblyReadinessRepositoryProvider),
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

// ═══════════════════════════════════════════════════════════════
// Phase 10 — Assembly Readiness
// ═══════════════════════════════════════════════════════════════

/// Readiness 行与 assembly 语义索引文档的持久化（Phase 10）。
final assemblyReadinessRepositoryProvider =
    Provider<IAssemblyReadinessRepository>((ref) {
  return AssemblyReadinessRepositoryImpl(
    getDb: () => DatabaseService.database,
  );
});

/// 从不可变 revision 构建运行时输出（fragments / worldview payload / 卡片行 /
/// 语义索引文档）。只读 revision，绝不读取 live tree。
final resourceAssemblyBuilderProvider = Provider<ResourceAssemblyBuilder>(
  (ref) {
    return ResourceAssemblyBuilder(
      revisionRepository: ref.watch(resourceRevisionRepositoryProvider),
      typeResolver: (id) async => ResourceTreeRepositoryImpl(
        getDb: () => DatabaseService.database,
      ).findResource(id).then((resource) => resource?.type),
    );
  },
);

/// 组装就绪协调器（Phase 10 核心）：
/// latest head → capacity/验证 → immutable build → head 复核 → assembly 发布
/// → 语义索引同步 → ready。OVERFLOW head 走已有 Phase 8 压缩准备并保持
/// preparing；所有终态写入都带 attempt-token CAS，迟到任务不能覆盖新任务。
///
/// 压缩挂接通过 [assemblyReadinessCompressionLinkProvider] 在启动时惰性接入，
/// 避免与 chatProvider → llmGateway 的静态 Provider 循环。
final assemblyReadinessCoordinatorProvider =
    Provider<AssemblyReadinessCoordinator>((ref) {
  return AssemblyReadinessCoordinator(
    getDb: () => DatabaseService.database,
    readinessRepository: ref.watch(assemblyReadinessRepositoryProvider),
    revisionRepository: ref.watch(resourceRevisionRepositoryProvider),
    revisionService: ref.watch(resourceRevisionServiceProvider),
    builder: ref.watch(resourceAssemblyBuilderProvider),
    typeResolver: (id) async => ResourceTreeRepositoryImpl(
      getDb: () => DatabaseService.database,
    ).findResource(id).then((resource) => resource?.type),
  );
});

/// 在启动时把 Phase 8 压缩基础设施挂接到 readiness 协调器。
final assemblyReadinessCompressionLinkProvider = Provider<void>((ref) {
  ref.read(assemblyReadinessCoordinatorProvider).attachCompression(
        coordinatorGetter: () => ref.read(compressionCoordinatorProvider),
        workerGetter: () => ref.read(compressionBackgroundWorkerProvider),
      );
});

/// Adventure 启动边界（Phase 10）：按被选资源解析 readiness，fail-closed
/// 阻止未就绪启动，并把被采用的 revision 冻结进 AdventureConfig。
final adventureReadinessGateProvider = Provider<IAdventureReadinessGate>((ref) {
  return AdventureReadinessGate(
    getDb: () => DatabaseService.database,
    treeRepository: ResourceTreeRepositoryImpl(
      getDb: () => DatabaseService.database,
    ),
    revisionRepository: ref.watch(resourceRevisionRepositoryProvider),
    revisionService: ref.watch(resourceRevisionServiceProvider),
    coordinator: ref.watch(assemblyReadinessCoordinatorProvider),
    builder: ref.watch(resourceAssemblyBuilderProvider),
  );
});
