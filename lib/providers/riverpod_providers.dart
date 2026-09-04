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
// Controllers
// ═══════════════════════════════════════════════════════════════

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
