import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/refresh/page_refresh_scope.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../../screens/chat/widgets/search_bar.dart';
import '../widgets/session_app_bar.dart';
import '../widgets/session_controls.dart';
import '../widgets/session_inspector.dart';
import '../../../../../models/app_section.dart';
import '../../../../../core/responsive/responsive.dart';
import 'model_select_page.dart';
import 'session_inspector_page.dart';
import '../widgets/session_input_bar.dart';
import '../widgets/session_message_list.dart';
import '../widgets/status_hud_bar.dart';
import '../../../../../l10n/generated/app_localizations.dart';
import '../../../../../l10n/generated/app_localizations_zh.dart';

/// Narrative reader with contextual controls and a responsive Inspector.
class AdventureSessionScreen extends ConsumerStatefulWidget {
  final VoidCallback? onMenuPressed;
  final String? initialMessageId;
  final bool? focusReading;
  final ValueChanged<bool>? onFocusReadingChanged;

  const AdventureSessionScreen({
    super.key,
    this.onMenuPressed,
    this.initialMessageId,
    this.focusReading,
    this.onFocusReadingChanged,
  });

  @override
  ConsumerState<AdventureSessionScreen> createState() =>
      _AdventureSessionScreenState();
}

class _AdventureSessionScreenState
    extends ConsumerState<AdventureSessionScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  bool _localFocusReading = false;
  // Last section visited in the Inspector page, restored on the next open.
  // Session presentation state only — never persisted.
  SessionInspectorSection _inspectorSection = SessionInspectorSection.scene;

  bool get _focusReading => widget.focusReading ?? _localFocusReading;

  void _toggleFocusReading() {
    final next = !_focusReading;
    if (widget.onFocusReadingChanged case final callback?) {
      callback(next);
    } else {
      setState(() => _localFocusReading = next);
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    ref.read(chatProvider).settingsProvider.updateBrightness(brightness);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage({String? overrideText}) {
    final text = overrideText ?? _textController.text.trim();
    if (text.isEmpty) return;

    final provider = ref.read(chatProvider);
    if (provider.isLoading || provider.isStreaming || provider.isSettling) {
      return;
    }

    if (overrideText == null) {
      _textController.clear();
    }
    provider.sendMessage(text);
  }

  void _showRuntimeState() =>
      ref.read(chatProvider).setCurrentSection(AppSection.runtimeState);

  void _showSceneCharacters() =>
      ref.read(chatProvider).setCurrentSection(AppSection.sceneCharacters);

  void _showModel() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ModelSelectPage(applyOnSelection: true)));

  /// Opens the Inspector as a real page. The result carries the last selected
  /// section so the next open can restore it.
  Future<void> _openInspectorPage(SessionInspectorSection section) async {
    final selected = await Navigator.of(context)
        .push<SessionInspectorSection>(MaterialPageRoute(
      builder: (_) => SessionInspectorPage(initialSection: section),
    ));
    if (selected != null && mounted) {
      setState(() => _inspectorSection = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = ref.watch(chatProvider);

    return PageRefreshScope(
      onRefresh: () async {
        final refreshed = await provider.refreshCurrentAdventure();
        return refreshed
            ? const PageRefreshResult.success()
            : PageRefreshResult.failure(l10n.adventureRefreshUnavailable);
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: SessionAppBar(
          onMenuPressed: widget.onMenuPressed,
          isFocusReading: _focusReading,
          onFocusReading: _toggleFocusReading,
          onInspector: () => _openInspectorPage(_inspectorSection),
        ),
        body: LayoutBuilder(builder: (context, constraints) {
          // The reader owns the whole session workspace; the Inspector is a
          // separate pushed page on every viewport.
          return Column(children: [
            if (!_focusReading) StatusHudBar(onTap: _showRuntimeState),
            if (provider.settingsProvider.searchVisible && !_focusReading)
              ChatSearchBar(onClose: provider.toggleSearch),
            Expanded(
                key: const ValueKey('session-reader'),
                child: SessionMessageList(
                  scrollController: _scrollController,
                  initialMessageId: widget.initialMessageId,
                  onStartAction: _focusNode.requestFocus,
                )),
            if (!_focusReading)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SessionControls(
                    onMenu: constraints.maxWidth < AppBreakpoints.mediumMin
                        ? widget.onMenuPressed
                        : null,
                    onContext: () =>
                        _openInspectorPage(SessionInspectorSection.context),
                    onCharacters: _showSceneCharacters,
                    onState: _showRuntimeState,
                    onModel: _showModel,
                  )),
            SessionInputBar(
                controller: _textController,
                focusNode: _focusNode,
                onSend: () => _sendMessage(),
                onStop: provider.cancelStreaming),
          ]);
        }),
      ),
    );
  }
}
