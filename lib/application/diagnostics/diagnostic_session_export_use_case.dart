import 'dart:io';

import '../../models/diagnostics/diagnostic_session_export.dart';
import '../../services/repositories/adventure_repository.dart';
import '../conversation/export_conversation_use_case.dart';
import 'diagnostic_sensitive_sanitizer.dart';

/// Builds a privacy-filtered diagnostic session export and persists it locally.
final class DiagnosticSessionExportUseCase {
  DiagnosticSessionExportUseCase({
    required IAdventureRepository repository,
    DiagnosticSensitiveSanitizer sanitizer =
        const DiagnosticSensitiveSanitizer(),
    ConversationExportUseCase fileWriter = const ConversationExportUseCase(),
  })  : _repository = repository,
        _sanitizer = sanitizer,
        _fileWriter = fileWriter;

  final IAdventureRepository _repository;
  final DiagnosticSensitiveSanitizer _sanitizer;
  final ConversationExportUseCase _fileWriter;

  /// Exports the current branch without changing any persisted application data.
  Future<String?> saveToFile({
    required int adventureId,
    required int branchId,
    int turnLimit = 30,
    String? title,
  }) async {
    final rawExport = await _repository.getDiagnosticSessionExport(
      adventureId: adventureId,
      branchId: branchId,
      turnLimit: turnLimit,
      platformName: Platform.operatingSystem,
    );
    final sanitizedJson = _sanitizer.sanitizeMap(rawExport.toJson());
    final sanitizedExport = DiagnosticSessionExport.fromJson(sanitizedJson);
    final filenameTitle = title?.trim().isNotEmpty == true
        ? title!.trim()
        : 'diagnostic_session_$adventureId';

    return _fileWriter.saveToFile(
      content: sanitizedExport.toPrettyJson(),
      extension: 'json',
      title: filenameTitle,
    );
  }
}
