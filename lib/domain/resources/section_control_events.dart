/// Phase 7 section-control events.
///
/// Every section state change produces exactly one typed event, so the UI,
/// tests and future persistence/replay layers observe the same facts instead
/// of re-deriving them. Events are immutable values: ordering is assigned by
/// the publishing bus (`SectionControlEventRecord.sequence`), which keeps the
/// domain free of global mutable state.
///
/// Pure Dart: no Flutter, no SQLite, no HTTP.
library;

import 'resource_contracts.dart';
import 'resource_edit_command.dart';
import 'section_control.dart';

/// Base type for everything that can happen to a controlled section.
sealed class SectionControlEvent {
  const SectionControlEvent({
    required this.resourceId,
    required this.sectionId,
    required this.timestamp,
  });

  final ResourceId resourceId;
  final SectionId sectionId;
  final DateTime timestamp;

  /// Stable event name used in logs and tests.
  String get eventName;
}

/// A section node was appended to a resource.
final class SectionCreatedEvent extends SectionControlEvent {
  const SectionCreatedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
    required this.title,
    this.orderIndex = 0,
  });

  final String title;
  final int orderIndex;

  @override
  String get eventName => 'SectionCreated';
}

/// Title or summary of a section changed.
final class SectionUpdatedEvent extends SectionControlEvent {
  const SectionUpdatedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
    this.title,
  });

  final String? title;

  @override
  String get eventName => 'SectionUpdated';
}

/// A section changed its sibling position.
final class SectionMovedEvent extends SectionControlEvent {
  const SectionMovedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
    required this.fromIndex,
    required this.toIndex,
  });

  final int fromIndex;
  final int toIndex;

  @override
  String get eventName => 'SectionMoved';
}

/// A section and its Parts were soft deleted.
final class SectionDeletedEvent extends SectionControlEvent {
  const SectionDeletedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
  });

  @override
  String get eventName => 'SectionDeleted';
}

/// Generation of a section's Parts started (or restarted).
final class SectionGenerationStartedEvent extends SectionControlEvent {
  const SectionGenerationStartedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
    required this.generationId,
    required this.mode,
    required this.partCount,
  });

  final String generationId;
  final AiRewriteMode mode;
  final int partCount;

  @override
  String get eventName => 'SectionGenerationStarted';
}

/// Every Part of a section finished generation.
final class SectionGenerationCompletedEvent extends SectionControlEvent {
  const SectionGenerationCompletedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
    required this.generationId,
    required this.completedPartCount,
    required this.characterCount,
  });

  final String generationId;
  final int completedPartCount;
  final int characterCount;

  @override
  String get eventName => 'SectionGenerationCompleted';
}

/// A section's generation stopped with an error.
final class SectionGenerationFailedEvent extends SectionControlEvent {
  const SectionGenerationFailedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
    required this.errorMessage,
    this.generationId = '',
  });

  final String generationId;
  final String errorMessage;

  @override
  String get eventName => 'SectionGenerationFailed';
}

/// A section's previously recorded validation verdict was invalidated.
///
/// Emitted when an edit makes the stored verdict stale, so a "valid" badge is
/// never shown for content that changed after validation.
final class SectionValidationResetEvent extends SectionControlEvent {
  const SectionValidationResetEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
    required this.reason,
  });

  final String reason;

  @override
  String get eventName => 'SectionValidationReset';
}

/// Validation of a section's committed content started.
final class SectionValidationStartedEvent extends SectionControlEvent {
  const SectionValidationStartedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
  });

  @override
  String get eventName => 'SectionValidationStarted';
}

/// A section passed validation and is now `valid`.
final class SectionValidationPassedEvent extends SectionControlEvent {
  const SectionValidationPassedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
    required this.characterCount,
  });

  final int characterCount;

  @override
  String get eventName => 'SectionValidationPassed';
}

/// A section failed validation and is now `invalid`.
final class SectionValidationFailedEvent extends SectionControlEvent {
  const SectionValidationFailedEvent({
    required super.resourceId,
    required super.sectionId,
    required super.timestamp,
    required this.issues,
    required this.errorMessage,
  });

  final List<SectionValidationIssue> issues;
  final String errorMessage;

  @override
  String get eventName => 'SectionValidationFailed';
}
