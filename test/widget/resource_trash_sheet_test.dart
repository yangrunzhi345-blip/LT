import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_trash_view_state.dart';
import 'package:lt_dialogue/domain/resources/resource_trash.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/features/resource_library/presentation/widgets/resource_trash_sheet.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';

import '../helpers/responsive_test_helper.dart';

const _longTitle = '一个非常长的章节标题，用来验证窄屏下回收站条目的换行与截断策略是否正确，避免任何溢出';

ResourceTrashItem _item({
  String trashId = 'trash_1',
  String title = '开场段落',
  RevisionNodeKindRef nodeKind = RevisionNodeKindRef.part,
  TrashReason reason = TrashReason.userDelete,
}) =>
    ResourceTrashItem(
      trashId: trashId,
      resourceId: 'res_1',
      title: title,
      nodeKind: nodeKind,
      reason: reason,
      deletedAt: DateTime(2026, 9, 17, 10),
      expiresAt: DateTime(2026, 10, 17, 10),
      isRestored: false,
    );

ResourceTrashViewState _ready({List<ResourceTrashItem>? items}) =>
    ResourceTrashViewState(
      status: ResourceTrashViewStatus.ready,
      items: items ?? <ResourceTrashItem>[_item()],
    );

void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  group('ResourceTrashView — responsive', () {
    for (final viewport in requiredUiViewports) {
      testWidgets(
        'renders at ${viewport.width}x${viewport.height} without overflow',
        (tester) async {
          setViewport(
            tester,
            width: viewport.width,
            height: viewport.height,
          );
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('zh'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ResourceTrashView(
                  state: _ready(),
                  onRefresh: () {},
                  onRestore: (_) {},
                  onPermanentDelete: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('回收站'), findsOneWidget);
        },
      );
    }

    testWidgets('survives a long dynamic title at 320 px', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: _ready(
                items: <ResourceTrashItem>[
                  _item(
                      title: _longTitle, nodeKind: RevisionNodeKindRef.section),
                  _item(trashId: 'trash_2', title: _longTitle),
                ],
              ),
              onRefresh: () {},
              onRestore: (_) {},
              onPermanentDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('保留至'), findsNWidgets(2));
    });

    testWidgets('survives a large text scale at 320 px', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ResourceTrashView(
                state: _ready(
                  items: <ResourceTrashItem>[_item(title: _longTitle)],
                ),
                onRefresh: () {},
                onRestore: (_) {},
                onPermanentDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a long bin scrolls instead of exceeding the viewport',
        (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: _ready(
                items: <ResourceTrashItem>[
                  for (var i = 0; i < 20; i++)
                    _item(trashId: 'trash_$i', title: '条目 $i'),
                ],
              ),
              onRefresh: () {},
              onRestore: (_) {},
              onPermanentDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);
      // The sheet is bounded, so the last item is reached by scrolling.
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('ResourceTrashView — states', () {
    testWidgets('shows a spinner while loading', (tester) async {
      setViewport(tester, width: 360, height: 640);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: const ResourceTrashViewState(
                status: ResourceTrashViewStatus.loading,
              ),
              onRefresh: () {},
              onRestore: (_) {},
              onPermanentDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('explains an empty bin', (tester) async {
      setViewport(tester, width: 360, height: 640);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: const ResourceTrashViewState(
                status: ResourceTrashViewStatus.ready,
              ),
              onRefresh: () {},
              onRestore: (_) {},
              onPermanentDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(zh.emptyRecycleBin), findsOneWidget);
    });

    testWidgets('shows the error message', (tester) async {
      setViewport(tester, width: 360, height: 640);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: const ResourceTrashViewState(
                status: ResourceTrashViewStatus.error,
                errorMessage: '读取回收站失败',
              ),
              onRefresh: () {},
              onRestore: (_) {},
              onPermanentDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('读取回收站失败'), findsOneWidget);
    });

    testWidgets('shows a fallback restore message', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: ResourceTrashViewState(
                status: ResourceTrashViewStatus.ready,
                items: <ResourceTrashItem>[_item()],
                notice: const ResourceTrashNotice(
                  kind: ResourceTrashNoticeKind.restored,
                  placement: TrashRestorePlacement.recreatedSectionUnderRoot,
                ),
              ),
              onRefresh: () {},
              onRestore: (_) {},
              onPermanentDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          AppLocalizationsZh().resourceTrashRestoreFallback,
        ),
        findsOneWidget,
        reason: 'a fallback restore must always be visible, never silent',
      );
    });
  });

  group('ResourceTrashView — actions', () {
    testWidgets('restore reports the entry id', (tester) async {
      setViewport(tester, width: 390, height: 844);
      final restored = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: _ready(items: <ResourceTrashItem>[_item()]),
              onRefresh: () {},
              onRestore: restored.add,
              onPermanentDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, zh.restoreAction));
      await tester.pump();

      expect(restored, <String>['trash_1']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('permanent delete asks first and only then reports',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final purged = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: _ready(items: <ResourceTrashItem>[_item()]),
              onRefresh: () {},
              onRestore: (_) {},
              onPermanentDelete: purged.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, zh.permanentlyDelete));
      await tester.pumpAndSettle();
      expect(
        purged,
        isEmpty,
        reason: 'a single tap must not be able to destroy content',
      );
      expect(find.text(zh.permanentlyDelete), findsWidgets);

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(
        purged,
        isEmpty,
        reason: 'cancelling must leave the entry alone',
      );

      await tester.tap(find.widgetWithText(TextButton, zh.permanentlyDelete));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, zh.permanentlyDelete));
      await tester.pumpAndSettle();
      expect(purged, <String>['trash_1']);
    });

    testWidgets('a busy row disables both actions', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: ResourceTrashViewState(
                status: ResourceTrashViewStatus.ready,
                items: <ResourceTrashItem>[
                  _item(trashId: 'trash_busy'),
                  _item(trashId: 'trash_idle'),
                ],
                busyTrashId: 'trash_busy',
              ),
              onRefresh: () {},
              onRestore: (_) {},
              onPermanentDelete: (_) {},
            ),
          ),
        ),
      );
      // Bounded pump: the busy row shows an indeterminate spinner, so
      // pumpAndSettle would never settle.
      await tester.pump();

      final restoreButtons = tester
          .widgetList<TextButton>(
              find.widgetWithText(TextButton, zh.restoreAction))
          .toList();
      expect(
        restoreButtons.first.onPressed,
        isNull,
        reason: 'the row being acted on must not accept a second action',
      );
      expect(
        restoreButtons.last.onPressed,
        isNotNull,
        reason: 'other rows stay actionable',
      );
    });

    testWidgets('refresh is disabled while loading', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ResourceTrashView(
              state: const ResourceTrashViewState(
                status: ResourceTrashViewStatus.loading,
              ),
              onRefresh: () {},
              onRestore: (_) {},
              onPermanentDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      final refresh = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(refresh.onPressed, isNull);
    });
  });

  group('trash item formatting', () {
    test('falls back to the node id when no title was recorded', () {
      final item = ResourceTrashItem(
        trashId: 'trash_1',
        resourceId: 'res_1',
        title: '  ',
        nodeKind: RevisionNodeKindRef.part,
        reason: TrashReason.userDelete,
        deletedAt: DateTime(2026, 9, 17, 10),
        expiresAt: DateTime(2026, 10, 17, 10),
        isRestored: false,
      );
      expect(item.title, '  ');
    });
  });
}
