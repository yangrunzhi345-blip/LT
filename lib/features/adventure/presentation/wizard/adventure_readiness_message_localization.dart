import '../../../../l10n/generated/app_localizations.dart';

/// Localizes the stable readiness message templates produced by the gate.
///
/// Readiness details remain diagnostic text from assembly validation; this
/// maps only the gate's user-facing framing and resource name.
String localizeAdventureReadinessMessage(
  String message,
  AppLocalizations l10n,
) {
  if (message == '该资源不属于统一资源库，不参与版本就绪检查') {
    return l10n.adventureAssetNotManaged;
  }
  if (message == '组装版本缺少角色卡，无法开始冒险') {
    return l10n.adventureAssemblyMissingCharacterCard;
  }
  if (message == '组装版本角色卡无法解析，无法开始冒险') {
    return l10n.adventureAssemblyInvalidCharacterCard;
  }

  final noSavedRevision =
      RegExp(r'^「(.*)」还没有已保存的版本，无法开始冒险$').firstMatch(message);
  if (noSavedRevision != null) {
    return l10n.adventureAssetNoSavedRevision(noSavedRevision.group(1)!);
  }

  final preparingWithDetails = RegExp(r'^「(.*)」准备中：(.+)$').firstMatch(message);
  if (preparingWithDetails != null) {
    return l10n.adventureAssetPreparingWithDetails(
      preparingWithDetails.group(1)!,
      preparingWithDetails.group(2)!,
    );
  }

  final preparing = RegExp(r'^「(.*)」正在组装准备，请稍候$').firstMatch(message);
  if (preparing != null) {
    return l10n.adventureAssetPreparing(preparing.group(1)!);
  }

  final failed = RegExp(r'^「(.*)」准备失败：(.+)$').firstMatch(message);
  if (failed != null) {
    return l10n.adventureAssetPreparationFailed(
      failed.group(1)!,
      failed.group(2)!,
    );
  }

  final ready = RegExp(r'^「(.*)」已就绪$').firstMatch(message);
  if (ready != null) return l10n.adventureAssetReady(ready.group(1)!);

  final noAssemblyRevision =
      RegExp(r'^「(.*)」尚无可用版本，请先完成资源组装准备$').firstMatch(message);
  if (noAssemblyRevision != null) {
    return l10n.adventureAssetNoAssemblyRevision(
      noAssemblyRevision.group(1)!,
    );
  }

  final stale = RegExp(r'^「(.*)」已修改，可使用上一个已就绪版本$').firstMatch(message);
  if (stale != null) {
    return l10n.adventureAssetStaleWithPrevious(stale.group(1)!);
  }

  return message;
}
