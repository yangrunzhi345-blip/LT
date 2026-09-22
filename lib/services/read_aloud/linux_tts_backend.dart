import 'linux_tts_backend_contract.dart';
import 'linux_tts_backend_platform_stub.dart'
    if (dart.library.io) 'linux_tts_backend_platform_io.dart' as platform;

export 'linux_tts_backend_contract.dart';

/// Creates the process implementation for the current Dart runtime.
LinuxTtsBackend createLinuxTtsBackend() => platform.createLinuxTtsBackend();
