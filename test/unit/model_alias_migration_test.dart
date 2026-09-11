import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lt_dialogue/models/llm_provider.dart';
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
    tempDir = await Directory.systemTemp.createTemp('lt_model_migration_');
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    settingsRepo =
        SettingsRepositoryImpl(getDb: () => DatabaseService.database);
  });

  tearDown(() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<SettingsProvider> loadProvider() async {
    final provider = SettingsProvider(
      settingsRepo: settingsRepo,
      connectivityStream: const Stream.empty(),
    );
    await provider.loadApiKey();
    return provider;
  }

  group('Model catalog alias migration', () {
    test('legacy flash alias migrates to deepseek-flash and is persisted',
        () async {
      await settingsRepo.setSettings({
        'llm_provider': 'deepseek',
        'llm_model': 'deepseek-v4-flash',
        'llm_model_deepseek': 'deepseek-v4-flash',
        'recent_models':
            'deepseek-v4-flash,deepseek-v4-flash-vision-exp,deepseek-v4-pro',
      });

      final settings = await loadProvider();

      expect(settings.modelName, 'deepseek-flash');
      expect(await settingsRepo.getSetting('llm_model_deepseek'),
          'deepseek-flash');
      expect(await settingsRepo.getSetting('llm_model'), 'deepseek-flash');
      // Recent list canonicalized and de-duplicated.
      expect(settings.recentModels, ['deepseek-flash', 'deepseek-v4-pro']);
      expect(await settingsRepo.getSetting('recent_models'),
          'deepseek-flash,deepseek-v4-pro');
    });

    test('vision-exp alias migrates to deepseek-flash', () async {
      await settingsRepo.setSettings({
        'llm_provider': 'deepseek',
        'llm_model_deepseek': 'deepseek-v4-flash-vision-exp',
      });

      final settings = await loadProvider();

      expect(settings.modelName, 'deepseek-flash');
      expect(await settingsRepo.getSetting('llm_model_deepseek'),
          'deepseek-flash');
    });

    test('legacy deepseek-v4-pro is preserved and hidden from the picker',
        () async {
      await settingsRepo.setSettings({
        'llm_provider': 'deepseek',
        'llm_model_deepseek': 'deepseek-v4-pro',
      });

      final settings = await loadProvider();

      expect(settings.modelName, 'deepseek-v4-pro');
      expect(await settingsRepo.getSetting('llm_model_deepseek'),
          'deepseek-v4-pro');
      expect(LLMProvider.deepseek.availableModels, ['deepseek-flash']);
      expect(LLMProvider.deepseek.knownModels, contains('deepseek-v4-pro'));
    });

    test('unknown deepseek model id falls back to the default', () async {
      await settingsRepo.setSettings({
        'llm_provider': 'deepseek',
        'llm_model_deepseek': 'deepseek-v5-unknown',
      });

      final settings = await loadProvider();

      expect(settings.modelName, 'deepseek-flash');
    });

    test('custom provider model id is never rewritten', () async {
      await settingsRepo.setEncryptedApiKey(
          'custom', KeyVault.encrypt('sk-custom'));
      await settingsRepo.setSettings({
        'llm_provider': 'custom',
        'llm_model_custom': 'gpt-4o',
      });

      final settings = await loadProvider();

      expect(settings.providerType, LLMProvider.custom);
      expect(settings.modelName, 'gpt-4o');
    });
  });
}
