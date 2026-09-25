import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/adventure_config.dart';
import 'package:lt_dialogue/features/adventure/presentation/home/widgets/dashboard_character_cards.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/screens/adventure_session_screen.dart';
import 'package:lt_dialogue/features/adventure/presentation/session/widgets/status_hud_bar.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart';
import 'package:lt_dialogue/features/resource_library/presentation/screens/resource_library_screen.dart';
import 'package:lt_dialogue/features/prompt_settings/presentation/screens/prompt_settings_screen.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

void main() {
  final l10n = AppLocalizationsZh();
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'openai_api_key': 'test', 'deepseek_api_key': 'test'});
    tempDir = await Directory.systemTemp.createTemp('lt_adv_test_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('Adventure Feature Unit & Widget Tests', () {
    for (final size in const [
      Size(320, 568),
      Size(360, 640),
      Size(393, 852),
      Size(411, 891),
      Size(600, 960),
      Size(568, 320),
    ]) {
      for (final scale in [1.0, 1.3, 1.5, 1.8]) {
        testWidgets('StatusHudBar should fit $size at text scale $scale',
            (tester) async {
          tester.view.reset();
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(ProviderScope(
            child: MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              ),
              home: const Scaffold(body: StatusHudBar()),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          for (final icon in [
            Icons.favorite_rounded,
            Icons.bolt_rounded,
            Icons.monetization_on_rounded,
            Icons.place_rounded
          ]) {
            expect(find.byIcon(icon), findsOneWidget);
            final bounds = tester.getRect(find.byIcon(icon));
            expect(bounds.left, greaterThanOrEqualTo(0));
            expect(bounds.right, lessThanOrEqualTo(size.width));
          }
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }

    testWidgets('StatusHudBar renders status elements', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const Scaffold(
              body: StatusHudBar(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);
      expect(find.byIcon(Icons.place_rounded), findsOneWidget);
    });

    testWidgets('AdventureWizardScreen renders stepper and advances steps',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(l10n.phaseWorldview), findsWidgets);
      expect(find.text(l10n.phaseCharacters), findsWidgets);
      expect(find.text(l10n.resourceNpcTab), findsWidgets);
      expect(find.text(l10n.phaseOpening), findsWidgets);
      expect(find.text(l10n.phasePreview), findsWidgets);
    });

    testWidgets(
        'AdventureWizardScreen should fit each step on mobile viewports',
        (tester) async {
      addTearDown(tester.view.reset);
      const viewports = [
        Size(320, 568),
        Size(360, 640),
        Size(393, 852),
        Size(411, 891),
        Size(600, 960),
        Size(568, 320),
      ];
      const textScales = [1.0, 1.3, 1.5];

      for (final size in viewports) {
        for (final scale in [...textScales, if (size.width == 320) 1.8]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                locale: const Locale('zh'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: child!,
                ),
                home: AdventureWizardScreen(onStartAdventure: (_) async {}),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          for (var step = 0; step < 5; step++) {
            final stepper = tester.widget<Stepper>(find.byType(Stepper));
            stepper.onStepTapped!(step);
            await tester.pump();
            expect(tester.takeException(), isNull,
                reason: '$size at $scale, step $step should not overflow');
          }
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    });

    testWidgets(
        'AdventureWizardScreen Step 1 renders AI worldview panel and creation buttons',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 验证步骤 1 世界观的 AI 创作与编写组件
      expect(find.text(l10n.worldSelectionTitle), findsOneWidget);
      expect(find.text(l10n.worldviewCreateAction), findsWidgets);
      expect(find.text(l10n.worldviewAiAssistantTitle), findsWidgets);
      expect(find.text(l10n.wizardWorldviewAiSummary), findsOneWidget);
      expect(find.text(l10n.wizardWorldviewPromptLabel), findsOneWidget);
      expect(find.text(l10n.wizardGenerateWorldviewAction), findsOneWidget);

      // 验证保存到资料库选项与按钮
      expect(find.text(l10n.autoSaveToLibrary), findsOneWidget);
      expect(find.text(l10n.saveToLibraryNow), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
    });

    testWidgets(
        'AdventureWizardScreen preview step exposes Save Preview without starting',
        (tester) async {
      var started = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async => started = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final stepper = tester.widget<Stepper>(find.byType(Stepper));
      stepper.onStepTapped!(4);
      await tester.pump();

      expect(find.text(l10n.savePreviewAction), findsOneWidget);
      expect(find.text(l10n.phasePreview), findsWidgets);

      await tester.ensureVisible(find.text(l10n.savePreviewAction));
      await tester.pump();
      await tester.tap(find.text(l10n.savePreviewAction));
      await tester.pump();
      expect(started, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'AdventureWizardScreen Step 2 allows adding character with role and relation',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 点击步骤 2: 角色设计
      final step2Title = find.text(l10n.phaseCharacters);
      expect(step2Title, findsWidgets);
      await tester.tap(step2Title.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(l10n.characterSelectionTitle), findsOneWidget);
      expect(find.text(l10n.newCharacterAction), findsOneWidget);
      expect(find.text(l10n.characterAiAssistantCreateTitle), findsWidgets);
      expect(
        find.text(l10n.wizardCharacterAiSummary(l10n.currentWorldviewLabel)),
        findsOneWidget,
      );
      expect(find.text(l10n.wizardGenerateMainCharacterAction), findsOneWidget);

      // 验证保存角色到资料库选项与按钮
      expect(find.text(l10n.autoSaveToLibrary), findsOneWidget);
      expect(find.text(l10n.saveToLibraryNow), findsOneWidget);

      // 点击新建角色打开资料库角色卡界面
      await tester.runAsync(() async {
        await tester.tap(find.text(l10n.newCharacterAction));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(find.text(l10n.characterCardCreateTitle), findsOneWidget);
      expect(find.text(l10n.characterCardInfoSection), findsOneWidget);
      expect(find.text(l10n.characterCardAiAssistedCreation), findsOneWidget);
      expect(find.text(l10n.aiFillIn), findsOneWidget);
      expect(find.text('${l10n.characterNameLabel} *'), findsOneWidget);
      expect(find.text(l10n.occupationLabel), findsOneWidget);
    });

    testWidgets(
        'AdventureWizardScreen Step 2 renders associated characters and relation selectors when characters exist',
        (tester) async {
      final config = AdventureConfig(
        worldview: '星穹世界',
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'c1',
            characterId: 'char_jinlan',
            characterName: '烬澜',
            characterAvatar: '',
            isProtagonist: true,
            narrativeRole: 'protagonist',
            customRoleName: '',
            sortOrder: 0,
            createdAt: '',
            updatedAt: '',
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              initialConfig: config,
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 点击步骤 2: 角色设计
      final step2Title = find.text(l10n.phaseCharacters);
      expect(step2Title, findsWidgets);
      await tester.tap(step2Title.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 验证关联已有角色设定区
      expect(
          find.text(l10n.characterCardRelateCharacterOptional), findsOneWidget);
      expect(find.text(l10n.selectRelatedCharacters), findsOneWidget);
      expect(find.text(l10n.characterCardBondRelation), findsOneWidget);
      expect(find.text(l10n.relationChildhoodFriend), findsWidgets);
      expect(find.text(l10n.relationLover), findsWidgets);
      expect(find.text(l10n.relationMentor), findsWidgets);
    });

    testWidgets(
        'AdventureWizardScreen keeps asset relationship as a suggestion while adventure relation is unset',
        (tester) async {
      final config = AdventureConfig(
        selectedCharacters: [
          AdventureSelectedCharacter(
            id: 'a',
            characterId: 'a',
            characterName: '艾琳',
            isProtagonist: true,
            characterCardJson: {
              'name': '艾琳',
              'description': '北境骑士',
              'relationship_links': [
                {
                  'targetResourceId': 'b',
                  'targetName': '莉亚',
                  'relationType': '姐妹',
                  'description': '关系紧张',
                },
              ],
            },
          ),
          AdventureSelectedCharacter(
            id: 'b',
            characterId: 'b',
            characterName: '莉亚',
            characterCardJson: {
              'name': '莉亚',
              'description': '宫廷学者',
            },
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              initialConfig: config,
              onStartAdventure: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(l10n.phaseCharacters).first);
      await tester.pump();

      expect(find.textContaining('姐妹'), findsOneWidget);
    });

    testWidgets(
        'AdventureWizardScreen Step 3 renders AI prologue generation panel and action branch fields',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 点击 Stepper 中的 "序章剧情" 步骤
      final step3Title = find.text(l10n.phaseOpening);
      expect(step3Title, findsWidgets);
      await tester.tap(step3Title.first);
      await tester.pumpAndSettle();

      // 验证 AI 智能编写面板
      expect(find.text(l10n.aiOpeningPanelTitle), findsOneWidget);
      expect(find.text(l10n.aiOpeningPanelDesc), findsOneWidget);
      expect(find.text(l10n.openingPromptLabel), findsOneWidget);
      expect(find.text(l10n.aiGenerateOpeningAndBranches), findsOneWidget);

      // 验证开场第一幕与行动分支
      expect(find.text(l10n.openingFirstSceneTitle), findsOneWidget);
      expect(find.text(l10n.initialActionBranchesTitle), findsOneWidget);
      expect(find.text(l10n.actionBranch1), findsOneWidget);
      expect(find.text(l10n.actionBranch2), findsOneWidget);
      expect(find.text(l10n.actionBranch3), findsOneWidget);
    });

    testWidgets('AdventureWizardScreen renders header and close button',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: AdventureWizardScreen(
              onStartAdventure: (cfg) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('定制冒险向导'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets(
        'AdventureSessionScreen renders blank slate empty state and input bar',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const AdventureSessionScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('纯净冒险白板'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    });

    testWidgets(
        'AdventureSessionScreen and ResourceLibraryScreen should fit on mobile',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      Widget scaled(Widget child) => MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            builder: (context, content) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.5),
              ),
              child: content!,
            ),
            home: child,
          );

      await tester.pumpWidget(
        ProviderScope(child: scaled(const AdventureSessionScreen())),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pump();
      expect(find.text('提示词设置'), findsOneWidget);
      expect(find.text(l10n.restartAdventureAction), findsOneWidget);
      expect(find.text(l10n.settingsCenter), findsOneWidget);

      await tester.pumpWidget(
        ProviderScope(child: scaled(const ResourceLibraryScreen())),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('resource-filter')), findsOneWidget);
      expect(find.byKey(const Key('resource-create-button')), findsOneWidget);
    });

    testWidgets('DashboardCharacterCards renders section title and icon',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: Scaffold(
              body: DashboardCharacterCards(
                onSelectCharacter: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('我的角色卡档案'), findsOneWidget);
      expect(find.byIcon(Icons.badge_outlined), findsOneWidget);
    });

    testWidgets(
        'PromptSettingsScreen renders dialogue level and prompt sections',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: AppTheme.light(),
            home: const PromptSettingsScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('提示词与推演编排'), findsOneWidget);
      expect(find.text(l10n.dialogueLevelSectionTitle), findsOneWidget);
      expect(find.text('全局系统提示词 (System Prompt)'), findsOneWidget);
      expect(find.text('作者注释 (Author\'s Note)'), findsOneWidget);
    });
    for (final size in const [Size(320, 568), Size(360, 640), Size(390, 844)]) {
      testWidgets('PromptSettingsScreen context weights fit $size',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: AppTheme.light(),
              home: const PromptSettingsScreen(),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text(l10n.contextWeightsTitle),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(l10n.contextWeightsTitle), findsOneWidget);
        expect(find.text(l10n.contextWeightsAdjust), findsOneWidget);
      });
    }
  });
}
