import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/feedback/app_feedback.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_radius.dart';
import 'core/theme/app_theme.dart';
import 'models/app_section.dart';
import 'models/resource_library_mode.dart';
import 'providers/chat_provider.dart';
import 'providers/riverpod_providers.dart';
import 'screens/adventure_mode_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/settings_center_screen.dart';
import 'screens/worldview_editor_screen.dart';
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
        final p = ref.read(chatProvider);
        return MaterialApp(
          title: 'LT Dialogue',
          navigatorKey: _appNavigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: p.themeMode,
          theme: AppTheme.light(colorSchemeSeed: p.colorSeed),
          darkTheme: AppTheme.dark(colorSchemeSeed: p.colorSeed),
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
  const MainGate({super.key});

  @override
  ConsumerState<MainGate> createState() => _MainGateState();
}

class _MainGateState extends ConsumerState<MainGate> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  bool _apiDialogShown = false;
  bool _isInitializing = true;
  String _initStatusText = '环境加载中...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeApp();
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
          if (mounted) {
            showApiSettings(context);
            _apiDialogShown = true;
          }
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isInitializing = false);

    if (!provider.isKeyConfigured && !_apiDialogShown) {
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

    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final sectionBody = _buildSectionBody(
      currentSection,
      currentAdventureId,
      isAdventureChatOpen,
      resourceLibraryMode,
      cp,
      isDesktop: isDesktop,
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: isDesktop ? null : buildMainSidebar(context, _scaffoldKey),
      body: isDesktop
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
    required bool isDesktop,
  }) {
    void onMenu() {
      if (isDesktop) {
        cp.toggleMainSidebarExpanded();
      } else {
        _scaffoldKey.currentState?.openDrawer();
      }
    }

    switch (section) {
      case AppSection.adventure:
        final advId = currentAdventureId;
        if (advId != null && isAdventureChatOpen) {
          return AdventureModeScreen(onMenuPressed: onMenu);
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
        return WorldviewEditorScreen(
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
                  Icons.auto_awesome,
                  size: 36,
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
