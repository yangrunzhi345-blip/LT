import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/resource_studio/domain/models/resource_revision_view_state.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/resource_revision_text.dart';
import 'package:lt_dialogue/features/resource_studio/presentation/widgets/resource_revision_panel.dart';

import '../helpers/responsive_test_helper.dart';

const _longLabel = '重新生成前的自动快照：包含一整段非常长的说明文字，用于验证窄屏换行与截断策略是否正确';

ResourceRevisionItem _item({
  String revisionId = 'rev_1',
  String label = 'AI 生成',
  bool isHead = false,
  int nodeCount = 12,
  int charCount = 4321,
}) =>
    ResourceRevisionItem(
      revisionId: revisionId,
      cause: RevisionCause.generation,
      label: label,
      createdAt: DateTime(2026, 9, 17, 10, 24),
      nodeCount: nodeCount,
      charCount: charCount,
      isHead: isHead,
    );

ResourceRevisionViewState _ready({
  List<ResourceRevisionItem>? items,
}) =>
    ResourceRevisionViewState(
      status: ResourceRevisionViewStatus.ready,
      resourceId: 'res_1',
      items: items ??
          <ResourceRevisionItem>[
            _item(revisionId: 'rev_head', isHead: true, label: '当前版本'),
            _item(revisionId: 'rev_old', label: '语义压缩'),
          ],
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: child),
      ),
    );

Future<void> _expandHistory(WidgetTester tester) async {
  await tester.tap(find.text('历史记录'));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('starts collapsed and toggles history', (tester) async {
    setViewport(tester, width: 390, height: 844);
    await tester.pumpWidget(
      _wrap(
        ResourceRevisionPanel(
          state: _ready(),
          onRefresh: () {},
          onRestore: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('恢复此记录'), findsNothing);

    await _expandHistory(tester);
    expect(find.text('恢复此记录'), findsNWidgets(2));

    await _expandHistory(tester);
    expect(find.text('恢复此记录'), findsNothing);
  });

  group('ResourceRevisionPanel — responsive', () {
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
            _wrap(
              ResourceRevisionPanel(
                state: _ready(),
                onRefresh: () {},
                onRestore: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('历史记录'), findsOneWidget);
        },
      );
    }

    testWidgets('survives a long dynamic label at 320 px', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        _wrap(
          ResourceRevisionPanel(
            state: _ready(
              items: <ResourceRevisionItem>[
                _item(label: _longLabel, charCount: 1234567890),
                _item(revisionId: 'rev_head', isHead: true, label: _longLabel),
              ],
            ),
            onRefresh: () {},
            onRestore: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandHistory(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('个节点'), findsNWidgets(2));
    });

    testWidgets('survives a large text scale at 320 px', (tester) async {
      setViewport(tester, width: 320, height: 568);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: _wrap(
            ResourceRevisionPanel(
              state: _ready(
                items: <ResourceRevisionItem>[_item(label: _longLabel)],
              ),
              onRefresh: () {},
              onRestore: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandHistory(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('ResourceRevisionPanel — states', () {
    testWidgets('shows a spinner while loading', (tester) async {
      setViewport(tester, width: 360, height: 640);
      await tester.pumpWidget(
        _wrap(
          ResourceRevisionPanel(
            state: const ResourceRevisionViewState(
              status: ResourceRevisionViewStatus.loading,
            ),
            onRefresh: () {},
            onRestore: (_) {},
          ),
        ),
      );
      await tester.pump();
      await _expandHistory(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('explains an empty history instead of showing nothing',
        (tester) async {
      setViewport(tester, width: 360, height: 640);
      await tester.pumpWidget(
        _wrap(
          ResourceRevisionPanel(
            state: const ResourceRevisionViewState(
              status: ResourceRevisionViewStatus.ready,
            ),
            onRefresh: () {},
            onRestore: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandHistory(tester);

      expect(find.text('还没有可恢复的历史记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the error message', (tester) async {
      setViewport(tester, width: 360, height: 640);
      await tester.pumpWidget(
        _wrap(
          ResourceRevisionPanel(
            state: const ResourceRevisionViewState(
              status: ResourceRevisionViewStatus.error,
              errorMessage: '读取历史记录失败',
            ),
            onRefresh: () {},
            onRestore: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandHistory(tester);

      expect(find.textContaining('读取历史记录失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the last restore outcome', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(
        _wrap(
          ResourceRevisionPanel(
            state: ResourceRevisionViewState(
              status: ResourceRevisionViewStatus.ready,
              items: <ResourceRevisionItem>[_item()],
              notice: const RevisionRestoreNotice(
                type: RevisionRestoreNoticeType.restored,
                sourceCause: RevisionCause.generation,
              ),
            ),
            onRefresh: () {},
            onRestore: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandHistory(tester);

      expect(
        find.text(
          resourceRevisionNoticeText(
            const RevisionRestoreNotice(
              type: RevisionRestoreNoticeType.restored,
              sourceCause: RevisionCause.generation,
            ),
            AppLocalizationsZh(),
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('ResourceRevisionPanel — actions', () {
    testWidgets('the head row cannot be restored', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(
        _wrap(
          ResourceRevisionPanel(
            state: _ready(
              items: <ResourceRevisionItem>[
                _item(revisionId: 'rev_head', isHead: true),
              ],
            ),
            onRefresh: () {},
            onRestore: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandHistory(tester);

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '恢复此记录'),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'restoring the version already in place would be a no-op',
      );
      expect(find.text('当前'), findsOneWidget);
    });

    testWidgets('restoring a historical version reports its id',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      final restored = <String>[];
      await tester.pumpWidget(
        _wrap(
          ResourceRevisionPanel(
            state: _ready(
              items: <ResourceRevisionItem>[
                _item(revisionId: 'rev_old'),
              ],
            ),
            onRefresh: () {},
            onRestore: restored.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandHistory(tester);

      final restoreButton = find.widgetWithText(TextButton, '恢复此记录');
      final restore = tester.widget<TextButton>(restoreButton).onPressed;
      expect(restore, isNotNull);
      restore!();
      await tester.pump();

      expect(restored, <String>['rev_old']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every restore button is disabled while a restore runs',
        (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(
        _wrap(
          ResourceRevisionPanel(
            state: ResourceRevisionViewState(
              status: ResourceRevisionViewStatus.ready,
              items: <ResourceRevisionItem>[
                _item(revisionId: 'rev_old'),
                _item(revisionId: 'rev_older'),
              ],
              canRestore: false,
            ),
            onRefresh: () {},
            onRestore: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _expandHistory(tester);

      final restoreButtons = find.widgetWithText(TextButton, '恢复此记录');
      expect(restoreButtons, findsNWidgets(2));
      for (final button in tester.widgetList<TextButton>(restoreButtons)) {
        expect(
          button.onPressed,
          isNull,
          reason: 'a second restore must not be able to race the first',
        );
      }
    });

    testWidgets('refresh is disabled while loading', (tester) async {
      setViewport(tester, width: 390, height: 844);
      await tester.pumpWidget(
        _wrap(
          ResourceRevisionPanel(
            state: const ResourceRevisionViewState(
              status: ResourceRevisionViewStatus.loading,
            ),
            onRefresh: () {},
            onRestore: (_) {},
          ),
        ),
      );
      await tester.pump();
      await _expandHistory(tester);

      final refresh = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.refresh),
      );
      expect(refresh.onPressed, isNull);
    });
  });

  group('revision item formatting', () {
    test('falls back to the cause when no label was recorded', () {
      final item = ResourceRevisionItem(
        revisionId: 'rev_1',
        cause: RevisionCause.generation,
        label: '',
        createdAt: DateTime(2026, 9, 17, 10, 24),
        nodeCount: 1,
        charCount: 2,
        isHead: false,
      );
      final l10n = lookupAppLocalizations(const Locale('zh'));
      expect(resourceRevisionTitle(item, l10n), 'AI 生成');
      expect(resourceRevisionSubtitle(item, l10n), contains('1 个节点'));
      expect(resourceRevisionSubtitle(item, l10n), contains('2 字'));
    });

    test('prefers an explicit label when one exists', () {
      final item = ResourceRevisionItem(
        revisionId: 'rev_1',
        cause: RevisionCause.compression,
        label: '压缩前快照',
        createdAt: DateTime(2026, 9, 17, 10, 24),
        nodeCount: 1,
        charCount: 2,
        isHead: false,
      );
      expect(
        resourceRevisionTitle(item, lookupAppLocalizations(const Locale('zh'))),
        '压缩前快照',
      );
    });

    test('localizes known generated labels and preserves custom labels', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        resourceRevisionTitle(
          _item(label: '恢复前'),
          l10n,
        ),
        l10n.revisionBeforeRestore,
      );
      expect(
        resourceRevisionTitle(
          _item(label: '语义压缩（节省 123 字）'),
          l10n,
        ),
        l10n.revisionCompressionSaved(123),
      );
      expect(
        resourceRevisionTitle(_item(label: 'My custom checkpoint'), l10n),
        'My custom checkpoint',
      );
    });
  });
}
