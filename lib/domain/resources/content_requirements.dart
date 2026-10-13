import 'dart:convert';

import 'resource_limits.dart';

/// The confirmed representation of a Part's body, independent of its title.
enum PartContentKind { narrative, scalar, structured }

/// Client-controlled rules; models cannot supply executable validators.
enum PartValidationProfile {
  narrativeSectionsV1,
  scalarTextV1,
  structuredObjectV1
}

/// Versioned requirements frozen with the blueprint, without rewriting bodies.
final class ContentRequirements {
  ContentRequirements({
    this.version = 1,
    required this.kind,
    required this.minimumCharacters,
    required this.validationProfile,
    this.required = true,
    List<String> requiredFields = const [],
    List<String> requiredHeadings = const [],
  })  : requiredFields = List.unmodifiable(requiredFields),
        requiredHeadings = List.unmodifiable(requiredHeadings);

  final int version;
  final PartContentKind kind;
  final bool required;
  final int minimumCharacters;
  final PartValidationProfile validationProfile;
  final List<String> requiredFields;
  final List<String> requiredHeadings;

  /// Rejects unsupported or inconsistent contracts before they can authorize AI.
  void validateDefinition() {
    final expectedProfile = switch (kind) {
      PartContentKind.narrative => PartValidationProfile.narrativeSectionsV1,
      PartContentKind.scalar => PartValidationProfile.scalarTextV1,
      PartContentKind.structured => PartValidationProfile.structuredObjectV1,
    };
    if (version != 1 ||
        minimumCharacters < 1 ||
        minimumCharacters > ResourceLimits.maxPartCharacters ||
        validationProfile != expectedProfile ||
        (kind != PartContentKind.structured && requiredFields.isNotEmpty) ||
        (kind == PartContentKind.structured && requiredFields.isEmpty) ||
        (kind != PartContentKind.narrative && requiredHeadings.isNotEmpty) ||
        !_validLabels(requiredFields) ||
        !_validLabels(requiredHeadings)) {
      throw const ContentRequirementException(
          ContentRequirementFailure.invalidContract);
    }
  }

  static bool _validLabels(List<String> values) =>
      values.length <= 24 &&
      values.toSet().length == values.length &&
      values.every((value) =>
          value.trim() == value &&
          value.isNotEmpty &&
          value.length <= 100 &&
          !value.contains('\n') &&
          !value.contains('\r'));

  Map<String, Object?> toMap() => {
        'version': version,
        'kind': kind.name,
        'required': required,
        'minimumCharacters': minimumCharacters,
        'validationProfile': validationProfile.name,
        'requiredFields': requiredFields,
        'requiredHeadings': requiredHeadings,
      };

  /// Reads only the known schema, preserving absence as legacy at the caller.
  factory ContentRequirements.fromMap(Map<String, Object?> map) {
    const keys = {
      'version',
      'kind',
      'required',
      'minimumCharacters',
      'validationProfile',
      'requiredFields',
      'requiredHeadings'
    };
    if (map.keys.any((key) => !keys.contains(key))) {
      throw const FormatException('Unknown content requirements field');
    }
    final version = map['version'];
    final minimum = map['minimumCharacters'];
    final required = map['required'];
    final kind = PartContentKind.values
        .where((value) => value.name == map['kind'])
        .firstOrNull;
    final profile = PartValidationProfile.values
        .where((value) => value.name == map['validationProfile'])
        .firstOrNull;
    if (version is! int ||
        minimum is! int ||
        required is! bool ||
        kind == null ||
        profile == null) {
      throw const FormatException('Invalid content requirements types');
    }
    List<String> labels(String key) {
      final value = map[key];
      if (value == null) return const [];
      if (value is! List || value.any((item) => item is! String)) {
        throw const FormatException('Invalid content requirements labels');
      }
      return value.cast<String>();
    }

    final result = ContentRequirements(
        version: version,
        kind: kind,
        minimumCharacters: minimum,
        validationProfile: profile,
        required: required,
        requiredFields: labels('requiredFields'),
        requiredHeadings: labels('requiredHeadings'));
    result.validateDefinition();
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is ContentRequirements &&
      version == other.version &&
      kind == other.kind &&
      required == other.required &&
      minimumCharacters == other.minimumCharacters &&
      validationProfile == other.validationProfile &&
      _equalLabels(requiredFields, other.requiredFields) &&
      _equalLabels(requiredHeadings, other.requiredHeadings);

  static bool _equalLabels(List<String> left, List<String> right) =>
      left.length == right.length &&
      List.generate(left.length, (i) => left[i] == right[i])
          .every((equal) => equal);

  @override
  int get hashCode => Object.hash(
      version,
      kind,
      required,
      minimumCharacters,
      validationProfile,
      Object.hashAll(requiredFields),
      Object.hashAll(requiredHeadings));
}

enum ContentRequirementFailure {
  invalidContract,
  belowMinimum,
  missingHeading,
  invalidScalar,
  invalidStructured,
  missingField
}

/// Carries safe failure metadata, never the rejected body or provider response.
final class ContentRequirementException implements Exception {
  const ContentRequirementException(this.reason, {this.minimum, this.actual});
  final ContentRequirementFailure reason;
  final int? minimum;
  final int? actual;
  @override
  String toString() => 'ContentRequirementException: ${reason.name}';
}

enum PartContentReview { validated, needsContentReview }

/// Deterministic content checks; these do not establish literary quality.
abstract final class PartContentRequirementsValidator {
  static PartContentReview validate(
      String body, ContentRequirements? requirements) {
    if (requirements == null) return PartContentReview.needsContentReview;
    requirements.validateDefinition();
    // Quality excludes outer padding; resource capacity still counts the entire
    // unchanged body in UTF-16 units at request/commit boundaries.
    final effectiveLength = body.trim().length;
    if (effectiveLength < requirements.minimumCharacters) {
      throw ContentRequirementException(ContentRequirementFailure.belowMinimum,
          minimum: requirements.minimumCharacters, actual: effectiveLength);
    }
    switch (requirements.validationProfile) {
      case PartValidationProfile.narrativeSectionsV1:
        // Check actual Markdown sections and their bodies, not self-reported coverage.
        final populatedHeadings = _populatedNarrativeHeadings(body);
        for (final heading in requirements.requiredHeadings) {
          if (!populatedHeadings.contains(heading)) {
            throw const ContentRequirementException(
                ContentRequirementFailure.missingHeading);
          }
        }
      case PartValidationProfile.scalarTextV1:
        if (body.trim().contains('\n') || body.trim().contains('\r')) {
          throw const ContentRequirementException(
              ContentRequirementFailure.invalidScalar);
        }
      case PartValidationProfile.structuredObjectV1:
        final Object? decoded;
        try {
          decoded = jsonDecode(body);
        } on FormatException {
          throw const ContentRequirementException(
              ContentRequirementFailure.invalidStructured);
        }
        if (decoded is! Map<String, Object?>) {
          throw const ContentRequirementException(
              ContentRequirementFailure.invalidStructured);
        }
        for (final field in requirements.requiredFields) {
          final value = decoded[field];
          if (value == null ||
              (value is String && value.trim().isEmpty) ||
              (value is List && value.isEmpty) ||
              (value is Map && value.isEmpty)) {
            throw const ContentRequirementException(
                ContentRequirementFailure.missingField);
          }
        }
    }
    return PartContentReview.validated;
  }

  // Only ATX headings are part of this controlled profile. Ignore fenced and
  // indented examples so model-authored demonstrations cannot assert coverage.
  static Set<String> _populatedNarrativeHeadings(String body) {
    final populated = <String>{};
    final fencePattern = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
    final headingPattern = RegExp(r'^ {0,3}#{1,6}[ \t]+(.+)$');
    String? fenceCharacter;
    var fenceLength = 0;
    String? currentHeading;
    for (final line in const LineSplitter().convert(body)) {
      final fence = fencePattern.firstMatch(line);
      if (fenceCharacter != null) {
        if (fence != null &&
            fence.group(1)!.startsWith(fenceCharacter) &&
            fence.group(1)!.length >= fenceLength &&
            fence.group(2)!.trim().isEmpty) {
          fenceCharacter = null;
        }
        continue;
      }
      if (fence != null) {
        fenceCharacter = fence.group(1)![0];
        fenceLength = fence.group(1)!.length;
        continue;
      }
      if (line.startsWith('    ') || line.startsWith('\t')) continue;
      final heading = headingPattern.firstMatch(line);
      if (heading != null) {
        currentHeading = heading
            .group(1)!
            .replaceFirst(RegExp(r'[ \t]+#+[ \t]*$'), '')
            .trim();
      } else if (currentHeading != null && line.trim().isNotEmpty) {
        populated.add(currentHeading);
      }
    }
    return populated;
  }
}
