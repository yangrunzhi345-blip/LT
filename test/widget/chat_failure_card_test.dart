import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/models/message.dart';
import 'package:lt_dialogue/screens/chat/widgets/error_card.dart';

void main() {
  for (final type in ['generation', 'internal', 'unknown']) {
    for (final width in [320.0, 360.0, 390.0, 412.0, 1024.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$type at width $width and text scale $scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: ErrorCard(
              message: Message(
                  id: 'failure',
                  content: 'private diagnostic',
                  isUser: false,
                  errorType: type),
              chatFontSize: 18,
              brightness: Brightness.light,
              onRetry: () {},
              onSwitchModel: () {},
            ))),
          ));
          await tester.pumpAndSettle();
          expect(find.text('网络错误'), findsNothing);
          expect(find.text(type == 'generation' ? '生成未完成' : '生成处理失败'),
              findsOneWidget);
          expect(find.text('private diagnostic'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  for (final locale in AppLocalizations.supportedLocales) {
    for (final type in ['generation', 'internal']) {
      testWidgets('$type localized at 320px: $locale', (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late AppLocalizations l10n;
        await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            l10n = AppLocalizations.of(context)!;
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            );
          },
          home: Scaffold(
              body: SingleChildScrollView(
                  child: ErrorCard(
            message: Message(
                id: 'localized',
                content: 'private diagnostic',
                isUser: false,
                errorType: type),
            chatFontSize: 18,
            brightness: Brightness.light,
            onRetry: () {},
            onSwitchModel: () {},
          ))),
        ));
        await tester.pumpAndSettle();
        expect(
            find.text(type == 'generation'
                ? l10n.errorGenerationIncompleteTitle
                : l10n.errorProcessingTitle),
            findsOneWidget);
        expect(find.text(l10n.errorNetworkTitle), findsNothing);
        expect(find.text('private diagnostic'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
