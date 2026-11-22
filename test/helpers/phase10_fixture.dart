import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/application/setting_cards/setting_card_adventure_snapshot.dart';
import 'package:lt_dialogue/domain/setting_cards/setting_card.dart';
import 'package:lt_dialogue/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'setting_card_fakes.dart';

/// Lightweight Phase 10 fixture.
///
/// Phase 5c retired the revision / assembly / compression pipeline, so the gate
/// the adventure start path uses is the card-only [SettingCardAwareReadinessGate].
/// The fixture keeps a real SQLite database (the start path still persists
/// there) plus an in-memory card store the gate reads from.
class Phase10Fixture {
  late Directory tempDir;
  late Database db;
  final MemorySettingCardRepository cards = MemorySettingCardRepository();
  late SettingCardAwareReadinessGate gate;

  Future<void> setUp({String prefix = 'lt_phase10_'}) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    tempDir = await Directory.systemTemp.createTemp(prefix);
    DatabaseService.customDbDir = tempDir.path;
    await DatabaseService.resetDatabase();
    db = await DatabaseService.database;
    gate = SettingCardAwareReadinessGate(cards: cards);
  }

  Future<void> tearDown() async {
    await DatabaseService.resetDatabase();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }

  /// Stores (or replaces) one card. Timestamps only need to be stable.
  Future<SettingCard> putCard({
    required String id,
    required SettingCardKind kind,
    required String name,
    String content = '',
    String summary = '',
    String originWorldviewId = '',
    bool deleted = false,
  }) async {
    final card = SettingCard(
      id: id,
      kind: kind,
      name: name,
      content: content,
      summary: summary,
      originWorldviewId: originWorldviewId,
      createdAt: '2026-01-01T00:00:00.000',
      updatedAt: '2026-01-01T00:00:00.000',
      deletedAt: deleted ? '2026-01-02T00:00:00.000' : null,
    );
    await cards.save(card);
    return card;
  }
}
