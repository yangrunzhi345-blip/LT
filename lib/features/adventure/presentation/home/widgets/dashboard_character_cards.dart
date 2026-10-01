import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/workbench_section.dart';
import '../../../../../models/character_card_entry.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

AppLocalizations _l10n(BuildContext context) =>
    AppLocalizations.of(context) ?? AppLocalizationsZh();

/// 首页“我的角色卡档案”流 (联动资料库 · 零预设白板)
class DashboardCharacterCards extends ConsumerStatefulWidget {
  final VoidCallback? onCreateCharacter;
  final ValueChanged<CharacterCardEntry> onSelectCharacter;

  const DashboardCharacterCards({
    super.key,
    this.onCreateCharacter,
    required this.onSelectCharacter,
  });

  @override
  ConsumerState<DashboardCharacterCards> createState() =>
      _DashboardCharacterCardsState();
}

class _DashboardCharacterCardsState
    extends ConsumerState<DashboardCharacterCards> {
  List<CharacterCardEntry> _cards = [];
  bool _loading = true;
  bool _hasLoadError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCards();
    });
  }

  Future<void> _loadCards() async {
    setState(() {
      _loading = true;
      _hasLoadError = false;
    });
    try {
      final setupController = ref.read(adventureSetupControllerProvider);
      await setupController.loadInitialData();
      if (mounted) {
        setState(() {
          _cards = setupController.characterCardEntries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _hasLoadError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n(context);
    return WorkbenchSection(
      title: l10n.dashboardMyCharacterCards,
      action: widget.onCreateCharacter == null
          ? null
          : TextButton(
              onPressed: widget.onCreateCharacter,
              child: Text(l10n.dashboardGoToLibrary)),
      child: _hasLoadError
          ? Column(children: [
              Text(l10n.pageLoadError),
              TextButton(onPressed: _loadCards, child: Text(l10n.retryAction))
            ])
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _cards.isEmpty
                  ? Text(l10n.dashboardNoCharacterCardsTitle)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          for (final card in _cards)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(card.name.isEmpty
                                    ? l10n.characterCardUnnamed
                                    : card.name),
                                subtitle: Text(
                                    [card.profession, card.personality]
                                        .where((value) => value.isNotEmpty)
                                        .join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                onTap: () => widget.onSelectCharacter(card),
                              ),
                            ),
                        ]),
    );
  }
}
