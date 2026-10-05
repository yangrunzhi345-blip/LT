import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/feedback/app_feedback.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_page_scaffold.dart';
import '../../../../core/widgets/app_svg_icon.dart';
import '../../../../core/widgets/workbench_section.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/generated/app_localizations_zh.dart';

/// Opens [uri] with the platform's default external handler and reports whether
/// it was accepted. Never throws: a rejected launch or a platform exception both
/// return `false` so the caller can surface a failure.
Future<bool> _launchExternally(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Dedicated "About project" destination.
///
/// Opened from the settings center: the project identity, source repository and
/// author contact live on their own navigable page instead of being stacked
/// onto the settings landing list.
class AboutProjectPage extends StatelessWidget {
  const AboutProjectPage(
      {super.key, this.launchExternalUrl = _launchExternally});

  /// External-launch seam so widget tests can exercise success/failure feedback
  /// without a real platform handler.
  final Future<bool> Function(Uri uri) launchExternalUrl;

  /// Authoritative external destinations, also asserted by the regression test.
  static const String repositoryUrl =
      'https://github.com/yangrunzhi345-blip/LT';
  static const String contactEmail = 'yangrunzhi345@gmail.com';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context) ?? AppLocalizationsZh();
    final theme = Theme.of(context);
    return AppPageScaffold(
      title: l10n.aboutProject,
      maxWidth: 640,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(l10n.appTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.aboutProjectDescription,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xl),
          WorkbenchSection(
            title: l10n.aboutSourceRepository,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  repositoryUrl,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('about-open-repository'),
                    onPressed: () => _openUrl(context, repositoryUrl, l10n),
                    icon: const AppSvgIcon('link', size: 18),
                    label: Text(l10n.aboutOpenRepository),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          WorkbenchSection(
            title: l10n.aboutContactAuthor,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  contactEmail,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('about-copy-email'),
                      onPressed: () => _copyEmail(context, l10n),
                      icon: const AppSvgIcon('copy', size: 18),
                      label: Text(l10n.aboutCopyEmail),
                    ),
                    OutlinedButton.icon(
                      key: const Key('about-send-email'),
                      onPressed: () => _openUrl(
                        context,
                        Uri(scheme: 'mailto', path: contactEmail).toString(),
                        l10n,
                      ),
                      icon: const AppSvgIcon('send', size: 18),
                      label: Text(l10n.aboutSendEmail),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyEmail(BuildContext context, AppLocalizations l10n) async {
    await Clipboard.setData(const ClipboardData(text: contactEmail));
    if (context.mounted) {
      AppFeedback.success(context, l10n.aboutEmailCopied);
    }
  }

  /// Opens [url] externally and always surfaces a failure instead of "nothing
  /// happening": a rejected launch or a platform exception both fall through
  /// to the localized error feedback.
  Future<void> _openUrl(
      BuildContext context, String url, AppLocalizations l10n) async {
    final opened = await launchExternalUrl(Uri.parse(url));
    if (!context.mounted) return;
    if (!opened) {
      AppFeedback.error(context, l10n.aboutOpenLinkFailed);
    }
  }
}
