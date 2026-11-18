import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/key_vault.dart';
import '../services/repositories/settings_repository.dart';

/// Platform credential store for provider API keys.
///
/// Implementations must never log, expose or persist key material except in
/// their own backend. [isAvailable] reports whether the *platform* backend can
/// be used; an unavailable backend must be handled by the caller, not by
/// throwing to UI code.
abstract interface class SecureKeyStore {
  /// Returns the plaintext key, or null when no key is stored.
  Future<String?> read(String provider);

  /// Persists [value]. An empty value is equivalent to [delete].
  Future<void> write(String provider, String value);

  /// Removes the key for [provider].
  Future<void> delete(String provider);

  /// Whether this backend can currently be used.
  Future<bool> isAvailable();
}

/// OS keychain / keystore backend.
///
/// Keys are stored as plaintext inside the platform credential store; the OS
/// owns encryption, access control and device binding. Availability varies by
/// platform (Linux may need libsecret), so callers must tolerate failures.
final class FlutterSecureKeyStore implements SecureKeyStore {
  const FlutterSecureKeyStore(
    this._storage, {
    this.keyPrefix = 'lt_api_key_',
  });

  final FlutterSecureStorage _storage;
  final String keyPrefix;

  String _storageKey(String provider) => '$keyPrefix$provider';

  @override
  Future<String?> read(String provider) =>
      _storage.read(key: _storageKey(provider));

  @override
  Future<void> write(String provider, String value) {
    if (value.isEmpty) return delete(provider);
    return _storage.write(key: _storageKey(provider), value: value);
  }

  @override
  Future<void> delete(String provider) =>
      _storage.delete(key: _storageKey(provider));

  @override
  Future<bool> isAvailable() async {
    try {
      // A read probe has no side effects and works on every supported backend.
      await _storage.read(key: '${keyPrefix}availability_probe');
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Legacy backend: KeyVault ciphertext in the `api_keys` SQLite table.
///
/// This is application-layer obfuscation, not a device-bound credential store.
/// It is kept as a fallback and as the migration source for [MigratingSecureKeyStore].
final class EncryptedDatabaseKeyStore implements SecureKeyStore {
  const EncryptedDatabaseKeyStore(this._repository);

  final ISettingsRepository _repository;

  @override
  Future<String?> read(String provider) async {
    final encrypted = (await _repository.getEncryptedApiKeys())[provider] ?? '';
    final opened = KeyVault.open(encrypted);
    if (opened == null) return null;

    // Keep upgrading pre-v2 records even when the platform store is not
    // available; the rewrite is conditional on the row being unchanged so a
    // concurrent writer is never overwritten.
    if (opened.usedLegacyFormat) {
      final current = (await _repository.getEncryptedApiKeys())[provider] ?? '';
      if (current == encrypted) {
        await _repository.setEncryptedApiKey(
          provider,
          KeyVault.encrypt(opened.plaintext),
        );
      }
    }
    return opened.plaintext;
  }

  @override
  Future<void> write(String provider, String value) =>
      _repository.setEncryptedApiKey(provider, KeyVault.encrypt(value));

  @override
  Future<void> delete(String provider) =>
      _repository.deleteEncryptedApiKey(provider);

  @override
  Future<bool> isAvailable() async => true;
}

/// Platform-first credential store with SQLite fallback and migration.
///
/// Read order: platform store → legacy `api_keys` ciphertext. A legacy value is
/// written to the platform store and the database ciphertext is removed only
/// after that write succeeds; on failure the database record stays for the next
/// attempt. Writes go to the platform store and clear stale database
/// ciphertext, falling back to the encrypted database only when the platform
/// backend fails.
///
/// Migration re-reads the platform store immediately before writing, so a
/// save that landed while the database record was being decrypted wins instead
/// of being overwritten. Operations are intentionally not queued: a stalled
/// platform channel must never block unrelated key reads. Diagnostics contain
/// only failure types and operation names — never key material, ciphertext or
/// tokens.
final class MigratingSecureKeyStore implements SecureKeyStore {
  MigratingSecureKeyStore({
    required this.primary,
    required this.fallback,
    this.onDiagnostic,
  });

  final SecureKeyStore primary;
  final SecureKeyStore fallback;
  final void Function(String message)? onDiagnostic;

  void _report(String message) =>
      (onDiagnostic ?? debugPrint)('[SecureKeyStore] $message');

  @override
  Future<String?> read(String provider) => _read(provider);

  Future<String?> _read(String provider) async {
    try {
      final value = await primary.read(provider);
      if (value != null && value.isNotEmpty) return value;
    } catch (error) {
      _report('read: platform backend failed (${error.runtimeType})');
    }

    final String? legacy;
    try {
      legacy = await fallback.read(provider);
    } catch (error) {
      _report(
          'read: encrypted database fallback failed (${error.runtimeType})');
      return null;
    }
    if (legacy == null || legacy.isEmpty) return null;

    // A save may have landed while the fallback record was being read; never
    // overwrite a newer platform value with the older migrated one.
    try {
      final current = await primary.read(provider);
      if (current != null && current.isNotEmpty && current != legacy) {
        _report('migration: newer platform value present; skipping');
        return current;
      }
    } catch (_) {
      // An unavailable platform read fails on the write below and takes the
      // database fallback path.
    }

    try {
      await primary.write(provider, legacy);
    } catch (error) {
      // The plaintext is still usable; keep the database record for a retry.
      _report('migration: platform write failed (${error.runtimeType}); '
          'keeping encrypted database record');
      return legacy;
    }

    try {
      final current = await fallback.read(provider);
      if (current == legacy) await fallback.delete(provider);
    } catch (error) {
      // The platform copy is already durable; a leftover database ciphertext
      // is harmless and will be cleaned up on a later migration attempt.
      _report('migration: database cleanup failed (${error.runtimeType})');
    }
    return legacy;
  }

  @override
  Future<void> write(String provider, String value) => _write(provider, value);

  Future<void> _write(String provider, String value) async {
    if (value.isEmpty) return _delete(provider);

    try {
      await primary.write(provider, value);
    } catch (error) {
      _report('write: platform backend failed (${error.runtimeType}); '
          'using encrypted database fallback');
      await fallback.write(provider, value);
      return;
    }
    try {
      await fallback.delete(provider);
    } catch (error) {
      _report('write: database cleanup failed (${error.runtimeType})');
    }
  }

  @override
  Future<void> delete(String provider) => _delete(provider);

  Future<void> _delete(String provider) async {
    try {
      await primary.delete(provider);
    } catch (error) {
      _report('delete: platform backend failed (${error.runtimeType})');
    }
    try {
      await fallback.delete(provider);
    } catch (error) {
      _report(
          'delete: encrypted database fallback failed (${error.runtimeType})');
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      return await primary.isAvailable();
    } catch (error) {
      _report('availability probe failed (${error.runtimeType})');
      return false;
    }
  }
}
