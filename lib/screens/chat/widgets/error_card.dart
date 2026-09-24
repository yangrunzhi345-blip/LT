import 'package:flutter/material.dart';
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
    IconData icon;
    String title;
    String? suggestion;
    switch (errorType) {
      case 'timeout':
        borderColor = Colors.orange.shade400;
        bgColor = isDark ? const Color(0xFF2A1E0A) : const Color(0xFFFFF8EE);
        icon = Icons.timer_off;
        title = l10n.errorTimeoutTitle;
        suggestion = l10n.errorTimeoutSuggestion;
        break;
      case 'auth':
        borderColor = Colors.pink.shade400;
        bgColor = isDark ? const Color(0xFF2A1A20) : const Color(0xFFFFF0F5);
        icon = Icons.key_off;
        title = l10n.errorAuthTitle;
        suggestion = l10n.errorAuthSuggestion;
        break;
      case 'rate':
        borderColor = Colors.amber.shade400;
        bgColor = isDark ? const Color(0xFF2A2408) : const Color(0xFFFFFDE8);
        icon = Icons.speed;
        title = l10n.errorRateTitle;
        suggestion = l10n.errorRateSuggestion;
        break;
      case 'api':
        borderColor = Colors.red.shade400;
        bgColor = isDark ? const Color(0xFF2A1A1A) : const Color(0xFFFFF5F5);
        icon = Icons.error_outline;
        title = l10n.errorApiTitle;
        suggestion = l10n.errorApiSuggestion;
        break;
      default:
        borderColor = Colors.red.shade400;
        bgColor = isDark ? const Color(0xFF2A1A1A) : const Color(0xFFFFF5F5);
        icon = Icons.wifi_off;
        title = l10n.errorNetworkTitle;
        suggestion = l10n.errorNetworkSuggestion;
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
              Icon(icon, size: 18, color: borderColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: chatFontSize - 1,
                  fontWeight: FontWeight.w600,
                  color: borderColor,
                ),
              ),
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
          Row(
            mainAxisSize: MainAxisSize.min,
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
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(l10n.retryAction,
                    style: const TextStyle(fontSize: 12)),
                onPressed: onRetry,
              ),
              const SizedBox(width: 8),
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
                icon: const Icon(Icons.swap_horiz, size: 16),
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
      default:
        return l10n.errorNetworkUnavailable;
    }
  }
}
