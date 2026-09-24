import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/features/adventure/presentation/wizard/adventure_readiness_message_localization.dart';
import 'package:lt_dialogue/application/adventure/adventure_readiness_gate.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_en.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_zh.dart';
import 'package:lt_dialogue/l10n/generated/app_localizations_ja.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('localizes readiness statuses and preserves dynamic details', () {
    expect(
      localizeAdventureReadinessMessage(
        '「Moon Garden」还没有已保存的版本，无法开始冒险',
        l10n,
      ),
      l10n.adventureAssetNoSavedRevision('Moon Garden'),
    );
    expect(
      localizeAdventureReadinessMessage(
        '「Moon Garden」准备中：Checking sections',
        l10n,
      ),
      l10n.adventureAssetPreparingWithDetails(
        'Moon Garden',
        'Checking sections',
      ),
    );
    expect(
      localizeAdventureReadinessMessage(
        '「Moon Garden」准备失败：Invalid section',
        l10n,
      ),
      l10n.adventureAssetPreparationFailed('Moon Garden', 'Invalid section'),
    );
    expect(
      localizeAdventureReadinessMessage('「Moon Garden」已就绪', l10n),
      l10n.adventureAssetReady('Moon Garden'),
    );
    expect(
      localizeAdventureReadinessMessage(
        '「Moon Garden」尚无可用版本，请先完成资源组装准备',
        l10n,
      ),
      l10n.adventureAssetNoAssemblyRevision('Moon Garden'),
    );
    expect(
      localizeAdventureReadinessMessage(
        '「Moon Garden」已修改，可使用上一个已就绪版本',
        l10n,
      ),
      l10n.adventureAssetStaleWithPrevious('Moon Garden'),
    );
  });

  test('localizes static readiness and assembly errors', () {
    expect(
      localizeAdventureReadinessMessage(
        '该资源不属于统一资源库，不参与版本就绪检查',
        l10n,
      ),
      l10n.adventureAssetNotManaged,
    );
    expect(
      localizeAdventureReadinessMessage('组装版本缺少角色卡，无法开始冒险', l10n),
      l10n.adventureAssemblyMissingCharacterCard,
    );
    expect(
      localizeAdventureReadinessMessage('组装版本角色卡无法解析，无法开始冒险', l10n),
      l10n.adventureAssemblyInvalidCharacterCard,
    );
  });

  test('maps typed diagnostics without relying on empty legacy details', () {
    const readiness = AdventureAssetReadiness(
      assetId: 'resource-1',
      status: AdventureAssetGateStatus.failed,
      issueCode: AdventureReadinessIssueCode.preparationFailed,
      parameters: {
        'name': 'Moon Garden',
        'diagnosticCode': 'preparationFailed',
      },
    );
    final zh = localizeAdventureReadiness(readiness, AppLocalizationsZh());
    final en = localizeAdventureReadiness(readiness, AppLocalizationsEn());
    final ja = localizeAdventureReadiness(readiness, AppLocalizationsJa());

    expect(zh, contains('资源准备失败'));
    expect(en, contains('Resource preparation failed'));
    expect(zh, isNot(contains('：\n')));
    expect(zh, isNot(en));
    expect(ja, contains('リソースの準備に失敗しました'));
    expect(ja, isNot(en));
  });
}
