import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

class PlatformUtils {
  PlatformUtils._();

  static bool get isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
}

/// Whether the current platform supports the gradient accent bar on AI bubbles.
///
/// The gradient accent bar (a 4px-wide LinearGradient Container inside ClipRRect)
/// was found to cause rendering failures on Android 16+ (including OriginOS 6)
/// due to Impeller GLES compositing layer issues in ListView rebuilds.
///
/// Affected platforms skip the gradient; all others get the visual enhancement.
bool get canUseGradientAccent {
  if (kIsWeb) return true;
  if (!Platform.isAndroid) return true; // iOS, Linux, macOS, Windows
  return _androidMajorVersion < 16;
}

int? _cachedAndroidMajorVersion;

int get _androidMajorVersion {
  if (_cachedAndroidMajorVersion != null) return _cachedAndroidMajorVersion!;

  final version = Platform.operatingSystemVersion;
  // Typical format: "Android 14 (API 34)" or "Android 16 (API 36)"
  final match = RegExp(r'Android\s+(\d+)').firstMatch(version);
  if (match == null) {
    // Unrecognized version format → conservative: assume problem exists
    _cachedAndroidMajorVersion = 16;
    return 16;
  }
  _cachedAndroidMajorVersion = int.tryParse(match.group(1)!) ?? 16;
  return _cachedAndroidMajorVersion!;
}
