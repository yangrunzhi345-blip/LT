import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lt_dialogue/providers/settings_provider.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:lt_dialogue/services/key_vault.dart';
import 'package:lt_dialogue/services/repositories/settings_repository_impl.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late Directory tempDir;
  late SettingsRepositoryImpl settingsRepo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('lt_key_migration_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    settingsRepo =
        SettingsRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('legacy API key is rewritten with v2 after a successful load', () async {
    const key = 'sk-legacy-migration';
    final legacyCiphertext = KeyVault.encryptLegacyForTest(key);
    await settingsRepo.setEncryptedApiKey('deepseek', legacyCiphertext);

    final provider = SettingsProvider(
      settingsRepo: settingsRepo,
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
    );
    addTearDown(provider.dispose);

    await provider.loadApiKey();
    expect(provider.apiKey, key);

    await provider.debugAwaitLegacyKeyMigration();

    final stored = (await settingsRepo.getEncryptedApiKeys())['deepseek']!;
    expect(stored, isNot(legacyCiphertext));
    final opened = KeyVault.open(stored);
    expect(opened, isNotNull);
    expect(opened!.plaintext, key);
    expect(opened.usedLegacyFormat, isFalse);
  });

  test('v2 API key is left untouched by the load path', () async {
    const key = 'sk-v2-existing';
    final v2Ciphertext = KeyVault.encrypt(key);
    await settingsRepo.setEncryptedApiKey('deepseek', v2Ciphertext);

    final provider = SettingsProvider(
      settingsRepo: settingsRepo,
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
    );
    addTearDown(provider.dispose);

    await provider.loadApiKey();
    expect(provider.apiKey, key);

    final stored = (await settingsRepo.getEncryptedApiKeys())['deepseek']!;
    expect(stored, v2Ciphertext);
  });
}
