import 'dart:io';

import '../../domain/tts/tts_errors.dart';

/// Classifies storage exhaustion by OS error number, retaining other failures.
TtsException ttsFileSystemFailure(
  Object error,
  TtsErrorCode fallback, {
  bool? isWindows,
  bool? isMacOS,
}) {
  final code = error is FileSystemException ? error.osError?.errorCode : null;
  final windows = isWindows ?? Platform.isWindows;
  final macOS = isMacOS ?? Platform.isMacOS;
  // Windows: ERROR_DISK_FULL / ERROR_HANDLE_DISK_FULL. POSIX: ENOSPC and
  // EDQUOT (Darwin uses 69; Linux/Android use 122).
  final exhausted = windows
      ? code == 112 || code == 39
      : code == 28 || code == (macOS ? 69 : 122);
  return TtsException(
    exhausted ? TtsErrorCode.insufficientStorage : fallback,
    cause: error,
  );
}
