import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lt_dialogue/core/theme/app_theme.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/tracked_state_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/widgets/tracked_state_library_surface.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/models/custom_attribute_item.dart';
import 'package:lt_dialogue/models/tracked_state_definition.dart';
import 'package:lt_dialogue/models/typed_runtime_state.dart';

const _curse = TrackedStateDefinition(
  id: 'curse',
  name: '诅咒侵蚀',
  valueKind: RuntimeStateValueKind.integer,
  minimum: 0,
  maximum: 100,
  importance: CustomAttributeImportance.critical,
  description: '接触污染时增加，净化时降低',
);

const _exposure = TrackedStateDefinition(
  id: 'exposure',
  name: '身份暴露风险',
  valueKind: RuntimeStateValueKind.integer,
  minimum: 0,
  maximum: 100,
  importance: CustomAttributeImportance.important,
);

const _warTension = TrackedStateDefinition(
  id: 'war_tension',
  name: '战争紧张度',
  valueKind: RuntimeStateValueKind.integer,
  minimum: 0,
  maximum: 100,
);

Widget _app(TrackedStateLibraryViewState state) => MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      home: Scaffold(
        body: TrackedStateLibrarySurface(
          state: state,
          onOpenOwner: (_) {},
          onEditOwner: (_) {},
          onAddStatus: () {},
          onRetry: () {},
          onPreviousPage: () {},
          onNextPage: () {},
        ),
      ),
    );

void main() {
  final l10n = AppLocalizationsZh();

  testWidgets('character surface lists monitored definitions without values',
      (tester) async {
    await tester.pumpWidget(_app(
      const TrackedStateLibraryViewState(
        status: TrackedStateLibraryStatus.ready,
        entries: [
          TrackedStateLibraryEntry(
            resourceId: 'c1',
            ownerType: ResourceType.character,
            ownerName: '艾莉丝',
            updatedAt: '2026-01-02',
            definitions: [_curse, _exposure],
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('诅咒侵蚀'), findsOneWidget);
    expect(find.text('身份暴露风险'), findsOneWidget);
    // Definitions only — never an adventure runtime current value.
    expect(find.textContaining('27'), findsNothing);
    expect(find.textContaining('37 / 100'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worldview surface lists monitored definitions', (tester) async {
    await tester.pumpWidget(_app(
      const TrackedStateLibraryViewState(
        status: TrackedStateLibraryStatus.ready,
        entries: [
          TrackedStateLibraryEntry(
            resourceId: 'w1',
            ownerType: ResourceType.worldview,
            ownerName: '艾尔德兰',
            updatedAt: '2026-01-03',
            definitions: [_warTension],
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('战争紧张度'), findsOneWidget);
    expect(find.textContaining('65'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('surface with no definitions shows a clear empty state',
      (tester) async {
    await tester.pumpWidget(_app(
      const TrackedStateLibraryViewState(
        status: TrackedStateLibraryStatus.ready,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(l10n.resourceTrackedStateEmptyTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
