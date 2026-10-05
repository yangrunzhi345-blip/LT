import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../domain/errors/app_error.dart';
import '../../services/api_error.dart';
import '../../services/llm_service.dart';
import '../../services/repositories/resource_tree_repository.dart';
import 'generation_patch_parser.dart';
import 'part_generation_parser.dart';
import 'part_generation_validator.dart';

/// The operation owning a failure, rather than a guess based on its text.
enum ResourceGenerationFailureStage { unknown, parsing, persistence, lifecycle }

/// Projects known failures to safe, stable codes without retaining payloads.
AppDomainError resourceGenerationError(
  Object error, {
  ResourceGenerationFailureStage stage = ResourceGenerationFailureStage.unknown,
}) {
  final code = switch (error) {
    AppDomainError value => value.code,
    ApiError value => value.code,
    LLMResponseIncompleteException() ||
    ReasoningOnlyResponseException() =>
      AppErrorCode.resourceProviderIncomplete,
    PartGenerationParseException() ||
    GenerationPatchParseException() =>
      AppErrorCode.resourceParseFailed,
    PartGenerationValidationException() => AppErrorCode.resourceContentInvalid,
    PatchSequenceGapException() ||
    PatchCursorMismatchException() =>
      AppErrorCode.resourceParseFailed,
    ResourceTreeConflictException() => AppErrorCode.resourceConflict,
    DatabaseException() => AppErrorCode.resourcePersistenceFailed,
    TimeoutException() => AppErrorCode.timeout,
    SocketException() ||
    TlsException() ||
    http.ClientException() =>
      AppErrorCode.networkUnavailable,
    String value => resourceGenerationErrorFromCode(value).code,
    _ => switch (stage) {
        ResourceGenerationFailureStage.parsing =>
          AppErrorCode.resourceParseFailed,
        ResourceGenerationFailureStage.persistence =>
          AppErrorCode.resourcePersistenceFailed,
        ResourceGenerationFailureStage.lifecycle =>
          AppErrorCode.resourceLifecycleFailed,
        ResourceGenerationFailureStage.unknown => AppErrorCode.unknown,
      },
  };
  return AppDomainError(code: code);
}

/// Historical diagnostics and unrecognized codes remain explicitly unknown.
AppDomainError resourceGenerationErrorFromCode(String value) {
  for (final code in AppErrorCode.values) {
    if (code.name == value) return AppDomainError(code: code);
  }
  return const AppDomainError(code: AppErrorCode.unknown);
}
