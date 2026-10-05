import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/features/settings/presentation/screens/about_project_page.dart';
import 'package:lt_dialogue/features/settings/presentation/screens/settings_pages.dart';
import 'package:lt_dialogue/services/database_service.dart';

import '../helpers/localization_test_helper.dart';
import '../helpers/responsive_test_helper.dart';

/// Regression guard for the settings-center "About" entry and its dedicated
/// page: the entry must stay reachable and the page must keep exposing the
/// source repository and author contact.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_about_test_');
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

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: localizedApp(home: const SettingsPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('settings center exposes the About entry and opens its page',
      (tester) async {
    setViewport(tester, width: 800, height: 900);
    await pumpSettings(tester);

    final entry = find.byKey(const Key('settings-about-entry'));
    expect(entry, findsOneWidget, reason: 'About entry must exist in settings');

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(AboutProjectPage), findsOneWidget);
    expect(find.text(AboutProjectPage.repositoryUrl), findsOneWidget);
    expect(find.text(AboutProjectPage.contactEmail), findsOneWidget);

    // Normal back navigation returns to the settings center.
    await localizedPageBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(AboutProjectPage), findsNothing);
  });

  testWidgets('about page is reachable on a narrow (320px) settings layout',
      (tester) async {
    setViewport(tester, width: 320, height: 900);
    await pumpSettings(tester);

    // A tall viewport keeps every settings row laid out so the entry is tappable.
    final entry = find.byKey(const Key('settings-about-entry'));
    expect(entry, findsOneWidget);

    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(AboutProjectPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('about page shows repository and contact, and copies the email',
      (tester) async {
    String? copiedText;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copiedText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(localizedApp(home: const AboutProjectPage()));
    await tester.pump();

    expect(find.text(AboutProjectPage.repositoryUrl), findsOneWidget);
    expect(find.text(AboutProjectPage.contactEmail), findsOneWidget);
    expect(find.byKey(const Key('about-copy-email')), findsOneWidget);

    await tester.tap(find.byKey(const Key('about-copy-email')));
    await tester.pump();

    expect(copiedText, AboutProjectPage.contactEmail);
    final feedback =
        tester.widget<Text>(find.byKey(const Key('app-feedback-message')));
    expect(feedback.data, '邮箱已复制到剪贴板');

    // Flush the feedback auto-dismiss timer so no timer leaks past the test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  });

  testWidgets('failing external link open surfaces an error, never silently',
      (tester) async {
    Uri? attempted;
    await tester.pumpWidget(localizedApp(
      home: AboutProjectPage(launchExternalUrl: (uri) async {
        attempted = uri;
        return false;
      }),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('about-open-repository')));
    await tester.pumpAndSettle();

    expect(attempted, Uri.parse(AboutProjectPage.repositoryUrl));
    final feedback =
        tester.widget<Text>(find.byKey(const Key('app-feedback-message')));
    expect(feedback.data, '无法打开链接，请手动复制后访问。');

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  });

  testWidgets('successful external link open shows no error feedback',
      (tester) async {
    await tester.pumpWidget(localizedApp(
      home: AboutProjectPage(launchExternalUrl: (_) async => true),
    ));
    await tester.pump();

    await tester.tap(find.byKey(const Key('about-open-repository')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('app-feedback-message')), findsNothing);
  });

  for (final viewport in requiredUiViewports) {
    testWidgets(
        'about page has no overflow at ${viewport.width}x${viewport.height}',
        (tester) async {
      setViewport(tester, width: viewport.width, height: viewport.height);
      await tester.pumpWidget(localizedApp(home: const AboutProjectPage()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('about-copy-email')), findsOneWidget);
    });
  }
}
