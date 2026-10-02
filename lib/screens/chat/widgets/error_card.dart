import 'package:flutter/material.dart';
import '../../../core/widgets/app_svg_icon.dart';
import '../../../models/message.dart';
import '../../../l10n/generated/app_localizations.dart';

class ErrorCard extends StatelessWidget {
  final Message message;
  final double chatFontSize;
  final Brightness brightness;
  final VoidCallback onRetry;
  final VoidCallback onSwitchModel;

  const ErrorCard({
    super.key,
    required this.message,
    required this.chatFontSize,
    required this.brightness,
    required this.onRetry,
    required this.onSwitchModel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final errorType = message.errorType;
    Color borderColor;
    Color bgColor;
    String icon;
    String title;
    String? suggestion;
    switch (errorType) {
      case 'timeout':
        borderColor = Colors.orange.shade400;
        bgColor = isDark ? const Color(0xFF2A1E0A) : const Color(0xFFFFF8EE);
        icon = 'warning';
        title = l10n.errorTimeoutTitle;
        suggestion = l10n.errorTimeoutSuggestion;
        break;
      case 'auth':
        borderColor = Colors.pink.shade400;
        bgColor = isDark ? const Color(0xFF2A1A20) : const Color(0xFFFFF0F5);
        icon = 'key';
        title = l10n.errorAuthTitle;
        suggestion = l10n.errorAuthSuggestion;
        break;
      case 'rate':
        borderColor = Colors.amber.shade400;
        bgColor = isDark ? const Color(0xFF2A2408) : const Color(0xFFFFFDE8);
        icon = 'speed';
        title = l10n.errorRateTitle;
        suggestion = l10n.errorRateSuggestion;
        break;
      case 'api':
        borderColor = Colors.red.shade400;
        bgColor = isDark ? const Color(0xFF2A1A1A) : const Color(0xFFFFF5F5);
        icon = 'error';
        title = l10n.errorApiTitle;
        suggestion = l10n.errorApiSuggestion;
        break;
      case 'network':
        borderColor = Colors.red.shade400;
        bgColor = isDark ? const Color(0xFF2A1A1A) : const Color(0xFFFFF5F5);
        icon = 'warning';
        title = l10n.errorNetworkTitle;
        suggestion = l10n.errorNetworkSuggestion;
        break;
      case 'generation':
      case 'internal':
      default:
        borderColor = Colors.red.shade400;
        bgColor = isDark ? const Color(0xFF2A1A1A) : const Color(0xFFFFF5F5);
        icon = 'error';
        title = errorType == 'generation'
            ? l10n.errorGenerationIncompleteTitle
            : l10n.errorProcessingTitle;
        suggestion = errorType == 'generation'
            ? l10n.errorGenerationIncompleteSuggestion
            : l10n.errorProcessingSuggestion;
        break;
    }
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 8, right: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(12),
        color: bgColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppSvgIcon(icon, size: 18, color: borderColor),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(
                title,
                style: TextStyle(
                  fontSize: chatFontSize - 1,
                  fontWeight: FontWeight.w600,
                  color: borderColor,
                ),
              )),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _localizedDetail(l10n, errorType),
            style: TextStyle(
              fontSize: chatFontSize - 1,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              height: 1.4,
            ),
          ),
          ...[
            const SizedBox(height: 4),
            Text(suggestion,
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.grey[500] : Colors.grey[500])),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: borderColor,
                  side: BorderSide(color: borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                icon: const AppSvgIcon('refresh', size: 16),
                label: Text(l10n.retryAction,
                    style: const TextStyle(fontSize: 12)),
                onPressed: onRetry,
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade300,
                  side: BorderSide(color: Colors.orange.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                icon: const AppSvgIcon('swap', size: 16),
                label: Text(l10n.switchModelRetry,
                    style: const TextStyle(fontSize: 12)),
                onPressed: onSwitchModel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _localizedDetail(AppLocalizations l10n, String? errorType) {
    switch (errorType) {
      case 'timeout':
        return l10n.errorRequestTimeout;
      case 'auth':
        return l10n.errorUnauthorized;
      case 'rate':
        return l10n.errorRateLimited;
      case 'api':
        return l10n.errorUnknown;
      case 'generation':
        return l10n.errorGenerationIncompleteDetail;
      case 'network':
        return l10n.errorNetworkUnavailable;
      case 'internal':
      default:
        return l10n.errorProcessingDetail;
    }
  }
}
