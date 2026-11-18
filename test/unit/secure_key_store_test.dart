import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/key_vault.dart';
import 'package:lt_dialogue/services/repositories/settings_repository.dart';
import 'package:lt_dialogue/services/secure_key_store.dart';

class _FakeStore implements SecureKeyStore {
  final Map<String, String> values = {};
  bool available = true;
  bool failRead = false;
  bool failWrite = false;
  bool failDelete = false;
  Completer<void>? readGate;
  final List<String> deleted = [];
  final List<String> written = [];

  @override
  Future<String?> read(String provider) async {
    if (failRead) throw StateError('platform-read-unavailable');
    final value = values[provider];
    final gate = readGate;
    if (gate != null) await gate.future;
    return value;
  }

  @override
  Future<void> write(String provider, String value) async {
    if (failWrite) throw StateError('platform-write-unavailable');
    written.add(provider);
    values[provider] = value;
  }

  @override
  Future<void> delete(String provider) async {
    if (failDelete) throw StateError('platform-delete-unavailable');
    deleted.add(provider);
    values.remove(provider);
  }

  @override
  Future<bool> isAvailable() async => available;
}

class _FakeSettingsRepo implements ISettingsRepository {
  final Map<String, String> encrypted = {};

  @override
  Future<Map<String, String>> getEncryptedApiKeys() async =>
      Map<String, String>.from(encrypted);

  @override
  Future<void> setEncryptedApiKey(String provider, String encryptedKey) async =>
      encrypted[provider] = encryptedKey;

  @override
  Future<void> deleteEncryptedApiKey(String provider) async =>
      encrypted.remove(provider);

  @override
  Future<void> addBookmark(int adventureId, int messageDbId) =>
      throw UnimplementedError();

  @override
  Future<void> removeBookmark(int adventureId, int messageDbId) =>
      throw UnimplementedError();

  @override
  Future<List<int>> getBookmarkedMessageIds(int adventureId) =>
      throw UnimplementedError();

  @override
  Future<void> deleteBookmarksByAdventure(int adventureId) =>
      throw UnimplementedError();

  @override
  Future<String?> getSetting(String key) => throw UnimplementedError();

  @override
  Future<void> setSetting(String key, String value) =>
      throw UnimplementedError();

  @override
  Future<void> setSettingInt(String key, int value) =>
      throw UnimplementedError();

  @override
  Future<int?> getSettingInt(String key) => throw UnimplementedError();

  @override
  Future<void> deleteSetting(String key) => throw UnimplementedError();

  @override
  Future<Map<String, String>> getAllSettings() => throw UnimplementedError();

  @override
  Future<void> setSettings(Map<String, String> values) =>
      throw UnimplementedError();

  @override
  Future<void> saveLlmConfiguration({
    required String provider,
    required String model,
    required String baseUrl,
    String? recentModels,
  }) =>
      throw UnimplementedError();
}

void main() {
  const provider = 'deepseek';
  const key = 'sk-platform-credential-test';

  late _FakeStore platform;
  late _FakeSettingsRepo repo;
  late EncryptedDatabaseKeyStore database;
  late List<String> diagnostics;
  late MigratingSecureKeyStore store;

  setUp(() {
    platform = _FakeStore();
    repo = _FakeSettingsRepo();
    database = EncryptedDatabaseKeyStore(repo);
    diagnostics = <String>[];
    store = MigratingSecureKeyStore(
      primary: platform,
      fallback: database,
      onDiagnostic: diagnostics.add,
    );
  });

  test('platform key is read without touching the encrypted database',
      () async {
    platform.values[provider] = key;
    repo.encrypted[provider] = KeyVault.encrypt('sk-stale-database-key');

    expect(await store.read(provider), key);
    expect(repo.encrypted[provider], isNotNull);
    expect(diagnostics, isEmpty);
  });

  test('legacy KeyVault ciphertext migrates to platform and is removed',
      () async {
    repo.encrypted[provider] = KeyVault.encryptLegacyForTest(key);

    expect(await store.read(provider), key);
    expect(platform.values[provider], key);
    expect(repo.encrypted.containsKey(provider), isFalse);
  });

  test('failed platform migration keeps the database record usable', () async {
    repo.encrypted[provider] = KeyVault.encrypt(key);
    platform.failWrite = true;

    expect(await store.read(provider), key);
    expect(platform.values.containsKey(provider), isFalse);
    expect(KeyVault.decrypt(repo.encrypted[provider]!), key);
    expect(diagnostics.join('\n'), contains('platform write failed'));
  });

  test('writes use the platform store and clear stale database ciphertext',
      () async {
    repo.encrypted[provider] = KeyVault.encrypt('sk-old-value');

    await store.write(provider, key);

    expect(platform.values[provider], key);
    expect(repo.encrypted.containsKey(provider), isFalse);
  });

  test('unavailable platform backend falls back to encrypted database',
      () async {
    platform.failWrite = true;

    await store.write(provider, key);

    expect(platform.values.containsKey(provider), isFalse);
    expect(KeyVault.decrypt(repo.encrypted[provider]!), key);
    expect(await store.read(provider), key);
    expect(diagnostics.join('\n'), contains('platform backend failed'));
  });

  test('delete removes the key from both backends', () async {
    platform.values[provider] = key;
    repo.encrypted[provider] = KeyVault.encrypt(key);

    await store.delete(provider);

    expect(platform.values.containsKey(provider), isFalse);
    expect(repo.encrypted.containsKey(provider), isFalse);
  });

  test('empty write is treated as delete', () async {
    platform.values[provider] = key;
    repo.encrypted[provider] = KeyVault.encrypt(key);

    await store.write(provider, '');

    expect(platform.values.containsKey(provider), isFalse);
    expect(repo.encrypted.containsKey(provider), isFalse);
  });

  test('migration never overwrites a save that landed while it was reading',
      () async {
    final legacy = _FakeStore()..values[provider] = 'sk-old-key';
    legacy.readGate = Completer<void>();
    final interleaved = MigratingSecureKeyStore(
      primary: platform,
      fallback: legacy,
      onDiagnostic: diagnostics.add,
    );
    const newest = 'sk-newest-key';

    final migration = interleaved.read(provider);
    // Wait until the migration has read the legacy value but not yet written.
    await Future<void>.delayed(Duration.zero);
    final save = interleaved.write(provider, newest);
    await save;
    legacy.readGate!.complete();

    expect(await migration, newest);
    expect(platform.values[provider], newest);
    expect(legacy.values.containsKey(provider), isFalse);
  });

  test('diagnostics never include key material or ciphertext', () async {
    final ciphertext = KeyVault.encrypt(key);
    repo.encrypted[provider] = ciphertext;
    platform.failWrite = true;
    platform.failDelete = true;

    await store.read(provider);
    await store.delete(provider);
    final report = diagnostics.join('\n');

    expect(report, isNot(contains(key)));
    expect(report, isNot(contains(ciphertext)));
  });

  test('isAvailable reflects the platform backend', () async {
    expect(await store.isAvailable(), isTrue);
    platform.available = false;
    expect(await store.isAvailable(), isFalse);
  });
}
