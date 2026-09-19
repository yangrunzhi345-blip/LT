import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/feedback/app_feedback.dart';
import 'core/responsive/responsive.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_radius.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'models/app_section.dart';
import 'models/resource_library_mode.dart';
import 'providers/chat_provider.dart';
import 'providers/riverpod_providers.dart';
import 'features/adventure/presentation/session/screens/adventure_session_screen.dart';
import 'features/resource_library/presentation/screens/resource_library_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/settings_center_screen.dart';
import 'services/adventure_start_guard.dart';
import 'widgets/app_dialogs.dart';
import 'widgets/main_sidebar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exception}\n${details.stack}');
  };
  ErrorWidget.builder = (details) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 48, color: Colors.orange),
                const SizedBox(height: 16),
                const Text('页面加载出错',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(details.exceptionAsString().split('\n').first,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    runApp(const MyApp());
                  },
                  child: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(child: _AppRoot());
  }
}

final GlobalKey<NavigatorState> _appNavigatorKey = GlobalKey<NavigatorState>();

class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cp = ref.read(chatProvider);
    return ValueListenableBuilder<int>(
      valueListenable: cp.themeVersion,
      builder: (context, _, __) {
        final p = cp;
        return MaterialApp(
          title: 'LT 灵境',
          navigatorKey: _appNavigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: p.themeMode,
          theme: AppTheme.light(colorSchemeSeed: p.colorSeed),
          darkTheme: AppTheme.dark(colorSchemeSeed: p.colorSeed),
          onGenerateRoute: AppRouter.onGenerateRoute,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final systemScale = mediaQuery.textScaler.scale(1.0);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(
                  systemScale * p.textScaleFactor,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyN, control: true):
                  () {
                ref.read(chatProvider).restartAdventure();
              },
            },
            child: const MainGate(),
          ),
        );
      },
    );
  }
}

class MainGate extends ConsumerStatefulWidget {
  const MainGate({
    super.key,
    this.showApiDialogOnInit = true,
    this.skipSplashOnInit = false,
  });

  final bool showApiDialogOnInit;
  final bool skipSplashOnInit;

  @override
  ConsumerState<MainGate> createState() => _MainGateState();
}

class _MainGateState extends ConsumerState<MainGate> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  bool _apiDialogShown = false;
  late bool _isInitializing;
  String _initStatusText = '环境加载中...';

  @override
  void initState() {
    super.initState();
    _isInitializing = !widget.skipSplashOnInit;
    if (!widget.skipSplashOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeApp();
      });
    }
    // Phase 8: the compression worker's startup hook. It reclaims jobs left
    // `running` by a process that died, independent of any screen being opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(compressionBackgroundWorkerProvider).start());
    });
    // Phase 9: the revision retention pass. Startup is the controlled point for
    // it — no edit can be in flight — and it runs at most once per interval, so
    // it cannot turn into a background load. Without a caller the chains grew
    // forever (audit P9-M3).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.read(revisionMaintenanceProvider).runIfDue());
    });
    // Phase 10: attach the compression infrastructure to the readiness
    // coordinator (lazy read avoids the chatProvider build cycle), then mark
    // `preparing` rows orphaned by a previous process as retryable failures —
    // fail-closed: they never auto-ready. Startup recovery must never crash
    // the app shell, so its failure is swallowed here (the row stays
    // `preparing`, which still blocks Adventure start).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(assemblyReadinessCompressionLinkProvider);
        unawaited(
          ref
              .read(assemblyReadinessCoordinatorProvider)
              .recoverInterrupted()
              .catchError((Object _) => 0),
        );
      } catch (_) {
        // Startup recovery is best-effort; readiness stays fail-closed.
      }
    });
    // Recover interrupted streaming sessions to a user-resumable state without
    // replaying billable model requests during application startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(streamingGenerationRecoveryProvider);
      } catch (_) {
        // Startup recovery is best-effort; the persisted state remains retryable.
      }
    });
  }

  Future<void> _initializeApp() async {
    if (!mounted) return;
    final provider = ref.read(chatProvider);

    await provider.loadApiKey();
    if (!mounted) return;

    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    if (provider.isKeyConfigured) {
      if (!mounted) return;
      setState(
          () => _initStatusText = '测试 ${provider.providerType.displayName}...');
      try {
        await provider.settingsProvider.testCurrentLlmConnection();
      } catch (_) {
        setState(() => _isInitializing = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.showApiDialogOnInit) {
            showApiSettings(context);
            _apiDialogShown = true;
          }
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isInitializing = false);

    if (widget.showApiDialogOnInit &&
        !provider.isKeyConfigured &&
        !_apiDialogShown) {
      _apiDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) showApiSettings(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return _buildSplashScreen();
    }

    final currentSection = ref.watch(
      chatProvider.select((cp) => cp.currentSection),
    );
    final currentAdventureId = ref.watch(
      chatProvider.select((cp) => cp.currentAdventureId),
    );
    final isAdventureChatOpen = ref.watch(
      chatProvider.select((cp) => cp.isAdventureChatOpen),
    );
    final resourceLibraryMode = ref.watch(
      chatProvider.select((cp) => cp.resourceLibraryMode),
    );
    final cp = ref.read(chatProvider);

    final isCompact = AppBreakpoints.isCompact(context);
    final isWideScreen = !isCompact;
    final isInAdventureSession = currentSection == AppSection.adventure &&
        isAdventureChatOpen &&
        currentAdventureId != null;

    final sectionBody = _buildSectionBody(
      currentSection,
      currentAdventureId,
      isAdventureChatOpen,
      resourceLibraryMode,
      cp,
      isWideScreen: isWideScreen,
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isWideScreen ? null : buildMainSidebar(context, _scaffoldKey),
      bottomNavigationBar: isCompact && !isInAdventureSession
          ? NavigationBar(
              selectedIndex: switch (currentSection) {
                AppSection.adventure => 0,
                AppSection.resources => 1,
                AppSection.settings => 2,
                _ => 0,
              },
              onDestinationSelected: (index) {
                switch (index) {
                  case 0:
                    cp.navigateToAdventureHome();
                    break;
                  case 1:
                    cp.openResourceLibrary(ResourceLibraryMode.adventure);
                    break;
                  case 2:
                    cp.setCurrentSection(AppSection.settings);
                    break;
                }
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: '探索',
                ),
                NavigationDestination(
                  icon: Icon(Icons.auto_stories_outlined),
                  selectedIcon: Icon(Icons.auto_stories_rounded),
                  label: '资料库',
                ),
                NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune_rounded),
                  label: '设置',
                ),
              ],
            )
          : null,
      body: isWideScreen
          ? Row(
              children: [
                buildMainSidebar(context, _scaffoldKey, permanent: true),
                Expanded(child: sectionBody),
              ],
            )
          : sectionBody,
    );
  }

  Widget _buildSectionBody(
    AppSection section,
    int? currentAdventureId,
    bool isAdventureChatOpen,
    ResourceLibraryMode resourceLibraryMode,
    ChatProvider cp, {
    required bool isWideScreen,
  }) {
    void onMenu() {
      if (isWideScreen) {
        cp.toggleMainSidebarExpanded();
      } else {
        _scaffoldKey.currentState?.openDrawer();
      }
    }

    switch (section) {
      case AppSection.adventure:
        final advId = currentAdventureId;
        if (advId != null && isAdventureChatOpen) {
          return AdventureSessionScreen(
            key: ValueKey('adventure_$advId'),
            onMenuPressed: onMenu,
          );
        }
        return LandingScreen(
          onMenuPressed: onMenu,
          onStartAdventure: (config, {difficulty}) async {
            if (!cp.isKeyConfigured) {
              showApiSettings(context);
              return;
            }
            try {
              await cp.startAdventureWithConfig(config);
            } on DuplicateStartIgnoredException {
              return;
            } catch (e, stack) {
              debugPrint('Failed to start adventure: $e');
              debugPrintStack(stackTrace: stack);
              if (!mounted) return;
              AppFeedback.error(context, '创建场景失败，请稍后重试');
            }
          },
        );

      case AppSection.resources:
        return ResourceLibraryScreen(
          mode: ResourceLibraryMode.adventure,
          onMenuPressed: onMenu,
        );

      case AppSection.settings:
        return SettingsCenterScreen(onMenuPressed: onMenu);

      default:
        return LandingScreen(
          onMenuPressed: onMenu,
          onStartAdventure: (config, {difficulty}) async {
            if (!cp.isKeyConfigured) {
              showApiSettings(context);
              return;
            }
            try {
              await cp.startAdventureWithConfig(config);
            } on DuplicateStartIgnoredException {
              return;
            } catch (e) {
              if (!mounted) return;
              AppFeedback.error(context, '创建场景失败，请稍后重试');
            }
          },
        );
    }
  }

  Widget _buildSplashScreen() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: isDark ? AppColors.darkBackground : AppColors.background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 34,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'LT Dialogue',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _initStatusText,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
