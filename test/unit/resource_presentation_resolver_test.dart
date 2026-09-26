import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/resources/resource_lifecycle_projection.dart';
import 'package:lt_dialogue/features/resource_library/domain/models/resource_library_view_state.dart';
import 'package:lt_dialogue/features/resource_library/presentation/resolvers/resource_presentation_resolver.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_en.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_ja.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_ko.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';

void main() {
  group('ResourcePresentationResolver Unit Tests', () {
    final l10nEn = AppLocalizationsEn();
    final l10nZh = AppLocalizationsZh();
    final l10nJa = AppLocalizationsJa();
    final l10nKo = AppLocalizationsKo();

    test('resolveLifecycle maps ResourceLifecycleState correctly', () {
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          lifecycleState: ResourceLifecycleState.planning,
        ),
        ResourcePresentationLifecycle.planning,
      );
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          lifecycleState: ResourceLifecycleState.generating,
        ),
        ResourcePresentationLifecycle.generating,
      );
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          lifecycleState: ResourceLifecycleState.validating,
        ),
        ResourcePresentationLifecycle.validating,
      );
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          lifecycleState: ResourceLifecycleState.recovering,
        ),
        ResourcePresentationLifecycle.recovering,
      );
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          lifecycleState: ResourceLifecycleState.ready,
        ),
        ResourcePresentationLifecycle.ready,
      );
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          lifecycleState: ResourceLifecycleState.failed,
        ),
        ResourcePresentationLifecycle.failed,
      );
    });

    test(
        'resolveLifecycle falls back to ResourceDisplayStatus with consumable flag',
        () {
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          displayStatus: ResourceDisplayStatus.ready,
          isConsumable: true,
        ),
        ResourcePresentationLifecycle.ready,
      );
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          displayStatus: ResourceDisplayStatus.optimizing,
        ),
        ResourcePresentationLifecycle.validating,
      );
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          displayStatus: ResourceDisplayStatus.saved,
          isConsumable: true,
        ),
        ResourcePresentationLifecycle.ready,
      );
      expect(
        ResourcePresentationResolver.resolveLifecycle(
          displayStatus: ResourceDisplayStatus.saved,
          isConsumable: false,
        ),
        ResourcePresentationLifecycle.draft,
      );
    });

    test('localizedLifecycleLabel returns localized text across all locales',
        () {
      // Ready
      expect(
        ResourcePresentationResolver.localizedLifecycleLabel(
          ResourcePresentationLifecycle.ready,
          l10nZh,
        ),
        '已准备完成',
      );
      expect(
        ResourcePresentationResolver.localizedLifecycleLabel(
          ResourcePresentationLifecycle.ready,
          l10nEn,
        ),
        'Ready',
      );
      expect(
        ResourcePresentationResolver.localizedLifecycleLabel(
          ResourcePresentationLifecycle.ready,
          l10nJa,
        ),
        '準備完了',
      );
      expect(
        ResourcePresentationResolver.localizedLifecycleLabel(
          ResourcePresentationLifecycle.ready,
          l10nKo,
        ),
        '준비 완료',
      );

      // Planning
      expect(
        ResourcePresentationResolver.localizedLifecycleLabel(
          ResourcePresentationLifecycle.planning,
          l10nZh,
        ),
        l10nZh.resourceLifecyclePlanning,
      );
      expect(
        ResourcePresentationResolver.localizedLifecycleLabel(
          ResourcePresentationLifecycle.planning,
          l10nEn,
        ),
        l10nEn.resourceLifecyclePlanning,
      );

      // Generating
      expect(
        ResourcePresentationResolver.localizedLifecycleLabel(
          ResourcePresentationLifecycle.generating,
          l10nZh,
        ),
        l10nZh.resourceLifecycleGenerating,
      );

      // Validating
      expect(
        ResourcePresentationResolver.localizedLifecycleLabel(
          ResourcePresentationLifecycle.validating,
          l10nZh,
        ),
        l10nZh.resourceLifecycleValidating,
      );

      // Failed
      expect(
        ResourcePresentationResolver.localizedLifecycleLabel(
          ResourcePresentationLifecycle.failed,
          l10nZh,
        ),
        l10nZh.resourceLifecycleFailed,
      );
    });

    test('isConsumableLabel distinguishes ready for adventure vs not', () {
      expect(
        ResourcePresentationResolver.isConsumableLabel(true, l10nZh),
        l10nZh.resourceConsumableBadge,
      );
      expect(
        ResourcePresentationResolver.isConsumableLabel(false, l10nZh),
        l10nZh.resourceNotConsumableBadge,
      );
      expect(
        ResourcePresentationResolver.isConsumableLabel(true, l10nEn),
        l10nEn.resourceConsumableBadge,
      );
      expect(
        ResourcePresentationResolver.isConsumableLabel(false, l10nEn),
        l10nEn.resourceNotConsumableBadge,
      );
    });

    test('inFlightStatusLabel returns label only when in flight', () {
      expect(
        ResourcePresentationResolver.inFlightStatusLabel(
          ResourcePresentationLifecycle.generating,
          l10nZh,
        ),
        l10nZh.resourceInFlightGenerating,
      );
      expect(
        ResourcePresentationResolver.inFlightStatusLabel(
          ResourcePresentationLifecycle.planning,
          l10nZh,
        ),
        l10nZh.resourceInFlightPlanning,
      );
      expect(
        ResourcePresentationResolver.inFlightStatusLabel(
          ResourcePresentationLifecycle.validating,
          l10nZh,
        ),
        l10nZh.resourceInFlightValidating,
      );
      expect(
        ResourcePresentationResolver.inFlightStatusLabel(
          ResourcePresentationLifecycle.recovering,
          l10nZh,
        ),
        l10nZh.resourceInFlightRecovering,
      );
      expect(
        ResourcePresentationResolver.inFlightStatusLabel(
          ResourcePresentationLifecycle.ready,
          l10nZh,
        ),
        isNull,
      );
      expect(
        ResourcePresentationResolver.inFlightStatusLabel(
          ResourcePresentationLifecycle.failed,
          l10nZh,
        ),
        isNull,
      );
    });

    group('Technical Desensitization and Safety Guard', () {
      test('strips forbidden identifiers and technical tokens', () {
        const leak1 = '资源 res_cre_1790430216927792_1 已创建';
        expect(
          ResourcePresentationResolver.sanitize(leak1).contains('res_cre_'),
          isFalse,
        );

        const leak2 = '蓝图 bp_123456_rev1 生成完成';
        expect(
          ResourcePresentationResolver.sanitize(leak2).contains('bp_'),
          isFalse,
        );

        const leak3 =
            '生成 task_res_cre_1_part_1 及 att_task_001_1790430217036899';
        final sanitized3 = ResourcePresentationResolver.sanitize(leak3);
        expect(sanitized3.contains('task_'), isFalse);
        expect(sanitized3.contains('att_'), isFalse);

        const leak4 = 'entityId: 99, revision: 3, CAS failure';
        final sanitized4 = ResourcePresentationResolver.sanitize(leak4);
        expect(sanitized4.contains('entityId'), isFalse);
        expect(sanitized4.contains('revision'), isFalse);
        expect(sanitized4.contains('CAS'), isFalse);

        const leak5 = 'file:///home/user/LT/data/database.sqlite';
        expect(
          ResourcePresentationResolver.sanitize(leak5).isEmpty,
          isTrue,
        );

        const leak6 = 'SELECT * FROM resources WHERE id = 1';
        expect(
          ResourcePresentationResolver.sanitize(leak6).contains('SELECT'),
          isFalse,
        );

        const leak7 = 'Exception: Unhandled null pointer\nStackTrace: #0 main';
        final sanitized7 = ResourcePresentationResolver.sanitize(leak7);
        expect(sanitized7.contains('Exception'), isFalse);
        expect(sanitized7.contains('StackTrace'), isFalse);

        const leak8 = '{"raw_json": {"nested": "value"}}';
        expect(
          ResourcePresentationResolver.sanitize(leak8).contains('raw_json'),
          isFalse,
        );
      });

      test(
          'safeName falls back when raw title is only technical tokens or empty',
          () {
        expect(
          ResourcePresentationResolver.safeName('res_cre_999999', l10nZh),
          l10nZh.resourceUnnamed,
        );
        expect(
          ResourcePresentationResolver.safeName('', l10nZh),
          l10nZh.resourceUnnamed,
        );
        expect(
          ResourcePresentationResolver.safeName('艾尔登法环', l10nZh),
          '艾尔登法环',
        );
      });

      test('safeSummary falls back when raw summary is empty or pure leak', () {
        expect(
          ResourcePresentationResolver.safeSummary('gen_cre_123456', l10nZh),
          l10nZh.resourceNoSummary,
        );
        expect(
          ResourcePresentationResolver.safeSummary('', l10nZh),
          l10nZh.resourceNoSummary,
        );
        expect(
          ResourcePresentationResolver.safeSummary('这是一段关于中土世界的描述。', l10nZh),
          '这是一段关于中土世界的描述。',
        );
      });
    });
  });
}
