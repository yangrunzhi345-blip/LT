/// Phase 7 binding checks for section-scoped generation.
///
/// Phase 7 must never generate JSON on its own: section (re)generation reuses
/// the frozen Phase 5 Incremental JSON Part Generation Protocol, so every patch
/// still carries `generationId` / `resourceId` / `sectionId` / `partId` from
/// [ResourceGenerationPatch].
///
/// This library adds one thing Phase 5 did not expose separately: a typed
/// section-scoped binding that names *which* identifier mismatched, so a stale
/// patch aimed at another section can be rejected with an actionable reason
/// instead of a generic identity error. It does not parse, re-serialize or
/// re-define the protocol.
library;

import 'resource_contracts.dart';
import 'resource_generation_patch.dart';
import 'resource_generation_protocol.dart';

/// Which identifier failed to match the expected binding.
enum SectionBindingField {
  generationId,
  resourceId,
  sectionId,
  partId;

  String get wireName => name;
}

/// Thrown when a patch or response does not belong to the expected binding.
///
/// A mismatched generation, resource, section or part must be rejected before
/// any state is written or any event is emitted.
class SectionGenerationBindingException implements Exception {
  const SectionGenerationBindingException({
    required this.field,
    required this.expected,
    required this.actual,
  });

  final SectionBindingField field;
  final String expected;
  final String actual;

  @override
  String toString() =>
      'SectionGenerationBindingException: ${field.wireName} mismatch '
      '(expected: $expected, actual: $actual)';
}

/// Identity one section-scoped generation attempt is bound to.
///
/// Phase 5 generates one Part at a time, so the binding pins all four ids:
/// `generationId`, `resourceId`, `sectionId` and `partId`.
final class SectionGenerationBinding {
  const SectionGenerationBinding({
    required this.generationId,
    required this.resourceId,
    required this.sectionId,
    required this.partId,
  }) : assert(generationId != '', 'generationId must not be empty');

  final String generationId;
  final ResourceId resourceId;
  final SectionId sectionId;
  final PartId partId;

  /// Returns true when [other] names the same generation, resource and section.
  bool covers(SectionGenerationBinding other) =>
      generationId == other.generationId &&
      resourceId == other.resourceId &&
      sectionId == other.sectionId;

  /// Validates one incremental patch against this binding.
  ///
  /// Field order is deliberate: generation first (a stale run), then resource,
  /// then section (a patch meant for a sibling section), then part. The first
  /// mismatch is thrown.
  void validatePatch(ResourceGenerationPatch patch) {
    _check(
      field: SectionBindingField.generationId,
      expected: generationId,
      actual: patch.generationId,
    );
    _check(
      field: SectionBindingField.resourceId,
      expected: resourceId.value,
      actual: patch.resourceId.value,
    );
    _check(
      field: SectionBindingField.sectionId,
      expected: sectionId.value,
      actual: patch.sectionId.value,
    );
    _check(
      field: SectionBindingField.partId,
      expected: partId.value,
      actual: patch.partId.value,
    );
  }

  /// Validates one validated Part response against this binding.
  void validateResponse(PartGenerationResponse response) {
    _check(
      field: SectionBindingField.generationId,
      expected: generationId,
      actual: response.generationId,
    );
    _check(
      field: SectionBindingField.resourceId,
      expected: resourceId.value,
      actual: response.resourceId.value,
    );
    _check(
      field: SectionBindingField.sectionId,
      expected: sectionId.value,
      actual: response.sectionId.value,
    );
    _check(
      field: SectionBindingField.partId,
      expected: partId.value,
      actual: response.partId.value,
    );
  }

  void _check({
    required SectionBindingField field,
    required String expected,
    required String actual,
  }) {
    if (expected != actual) {
      throw SectionGenerationBindingException(
        field: field,
        expected: expected,
        actual: actual,
      );
    }
  }

  @override
  String toString() => 'SectionGenerationBinding(gen: $generationId, '
      'res: ${resourceId.value}, sec: ${sectionId.value}, '
      'part: ${partId.value})';
}
