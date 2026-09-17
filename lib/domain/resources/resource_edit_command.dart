/// Phase 7 node-scoped edit commands.
///
/// Every Studio action that changes one node goes through exactly one command
/// object. The command layer is what makes the rules auditable:
/// - one command touches one target node (or one sibling order list);
/// - every mutating command carries the `expectedUpdatedAt` optimistic-locking
///   token, so two concurrent edits cannot silently overwrite each other;
/// - AI commands carry only a bounded instruction, never a whole resource.
///
/// Pure Dart: no Flutter, no SQLite, no HTTP. Execution lives in
/// `application/resources/section_control_service.dart`, which reads the
/// frozen Phase 0 repositories instead of re-implementing persistence.
library;

import 'resource_contracts.dart';
import 'resource_limits.dart';

/// Thrown when a command is structurally invalid before any I/O happens.
class ResourceEditCommandException implements Exception {
  const ResourceEditCommandException({
    required this.message,
    this.field = '',
  });

  final String message;
  final String field;

  @override
  String toString() => 'ResourceEditCommandException: $message'
      '${field.isNotEmpty ? ' [field: $field]' : ''}';
}

/// How an AI rewrite of one node should behave.
///
/// Regeneration replaces the whole node body; the other three are bounded
/// transformations of the existing body, so the prompt stays node-scoped.
enum AiRewriteMode {
  regenerate('regenerate'),
  rewrite('rewrite'),
  expand('expand'),
  condense('condense');

  const AiRewriteMode(this.storageValue);

  final String storageValue;

  /// Regeneration and rewrite replace content; expand/condense transform it.
  bool get replacesContent => this == AiRewriteMode.regenerate;

  /// Prompt directive prepended to the user instruction for this mode.
  ///
  /// Empty for [regenerate] so a "regenerate" run produces exactly the same
  /// prompt as the original generation; the other modes narrow the model's job.
  String get directive => switch (this) {
        AiRewriteMode.regenerate => '',
        AiRewriteMode.rewrite => '请在保持既有事实与设定一致的前提下，完整重写当前 Part 的正文。',
        AiRewriteMode.expand => '请在保持既有事实与设定一致的前提下，扩写当前 Part 的正文，补充细节。',
        AiRewriteMode.condense => '请在保持既有事实与设定一致的前提下，压缩当前 Part 的正文，删除冗余表述。',
      };
}

/// One finite node-scoped edit requested by the user or the UI.
///
/// The sealed hierarchy is intentionally small: there is no command that takes
/// a serialized whole resource, and no command that edits several unrelated
/// nodes at once.
sealed class ResourceEditCommand {
  const ResourceEditCommand({this.expectedUpdatedAt = ''});

  /// Optimistic-locking token read from the node before the edit.
  ///
  /// Empty only for creation, which has no previous version to protect.
  final String expectedUpdatedAt;

  /// Human readable command kind, used in diagnostics and events.
  String get commandKind;
}

/// Appends one new section directly under a resource.
final class CreateSectionCommand extends ResourceEditCommand {
  const CreateSectionCommand({
    required this.resourceId,
    required this.title,
    this.summary = '',
  });

  final ResourceId resourceId;
  final String title;
  final String summary;

  @override
  String get commandKind => 'create_section';
}

/// Renames exactly one section.
final class RenameSectionCommand extends ResourceEditCommand {
  const RenameSectionCommand({
    required this.sectionId,
    required this.title,
    required super.expectedUpdatedAt,
  });

  final SectionId sectionId;
  final String title;

  @override
  String get commandKind => 'rename_section';
}

/// Updates title and/or summary of exactly one section.
final class UpdateSectionCommand extends ResourceEditCommand {
  const UpdateSectionCommand({
    required this.sectionId,
    required super.expectedUpdatedAt,
    this.title,
    this.summary,
  });

  final SectionId sectionId;
  final String? title;
  final String? summary;

  @override
  String get commandKind => 'update_section';
}

/// Moves one section to an explicit sibling position.
final class MoveSectionCommand extends ResourceEditCommand {
  const MoveSectionCommand({
    required this.resourceId,
    required this.sectionId,
    required this.targetIndex,
    required super.expectedUpdatedAt,
  });

  final ResourceId resourceId;
  final SectionId sectionId;
  final int targetIndex;

  @override
  String get commandKind => 'move_section';
}

/// Soft deletes exactly one section and its Parts.
final class DeleteSectionCommand extends ResourceEditCommand {
  const DeleteSectionCommand({
    required this.sectionId,
    required super.expectedUpdatedAt,
  });

  final SectionId sectionId;

  @override
  String get commandKind => 'delete_section';
}

/// Updates title and/or body of exactly one Part.
///
/// [sectionId] is carried so the service can invalidate the owning section's
/// validation result in the same operation: editing body text makes a previous
/// "valid" verdict stale.
final class UpdatePartCommand extends ResourceEditCommand {
  const UpdatePartCommand({
    required this.sectionId,
    required this.partId,
    required super.expectedUpdatedAt,
    this.title,
    this.content,
  });

  final SectionId sectionId;
  final PartId partId;
  final String? title;
  final String? content;

  @override
  String get commandKind => 'update_part';
}

/// Moves one Part to an explicit sibling position inside its section.
final class MovePartCommand extends ResourceEditCommand {
  const MovePartCommand({
    required this.sectionId,
    required this.partId,
    required this.targetIndex,
    required super.expectedUpdatedAt,
  });

  final SectionId sectionId;
  final PartId partId;
  final int targetIndex;

  @override
  String get commandKind => 'move_part';
}

/// Soft deletes exactly one Part.
final class DeletePartCommand extends ResourceEditCommand {
  const DeletePartCommand({
    required this.sectionId,
    required this.partId,
    required super.expectedUpdatedAt,
  });

  final SectionId sectionId;
  final PartId partId;

  @override
  String get commandKind => 'delete_part';
}

/// Requests a bounded AI transformation of exactly one section.
///
/// Execution stays inside the Phase 5 protocol: only the section's own Part
/// tasks are re-run, never a single whole-resource call.
final class RegenerateSectionCommand extends ResourceEditCommand {
  const RegenerateSectionCommand({
    required this.sectionId,
    super.expectedUpdatedAt,
    this.mode = AiRewriteMode.regenerate,
    this.instruction = '',
  });

  final SectionId sectionId;
  final AiRewriteMode mode;

  /// Extra user instruction. Bounded by the validator so a prompt can never
  /// grow into a full-resource payload.
  final String instruction;

  @override
  String get commandKind => 'regenerate_section';
}

/// Structural validation for [ResourceEditCommand]s.
///
/// This validator never touches the database: it rejects malformed input
/// before any I/O, and the service still enforces existence, ownership and
/// optimistic locking against real rows.
abstract final class ResourceEditCommandValidator {
  /// Maximum title length for a section or part.
  ///
  /// Titles are navigation labels, not content, so they stay well below the
  /// capacity budget; the limit only exists to stop accidental paste bombs.
  static const int maxTitleLength = 200;

  /// Maximum summary length for a section.
  static const int maxSummaryLength = 2000;

  /// Maximum length of a user instruction attached to an AI command.
  static const int maxInstructionLength = 2000;

  static void validate(ResourceEditCommand command) {
    switch (command) {
      case CreateSectionCommand():
        _requireTitle(command.title);
        _requireMax(
          value: command.summary,
          max: maxSummaryLength,
          field: 'summary',
        );
      case RenameSectionCommand():
        _requireToken(command.expectedUpdatedAt);
        _requireTitle(command.title);
      case UpdateSectionCommand():
        _requireToken(command.expectedUpdatedAt);
        if (command.title == null && command.summary == null) {
          throw const ResourceEditCommandException(
            message: 'Section 更新必须至少包含 title 或 summary',
            field: 'title',
          );
        }
        if (command.title != null) _requireTitle(command.title!);
        if (command.summary != null) {
          _requireMax(
            value: command.summary!,
            max: maxSummaryLength,
            field: 'summary',
          );
        }
      case MoveSectionCommand():
        _requireToken(command.expectedUpdatedAt);
        _requireIndex(command.targetIndex, 'targetIndex');
      case DeleteSectionCommand():
        _requireToken(command.expectedUpdatedAt);
      case UpdatePartCommand():
        _requireToken(command.expectedUpdatedAt);
        if (command.title == null && command.content == null) {
          throw const ResourceEditCommandException(
            message: 'Part 更新必须至少包含 title 或 content',
            field: 'title',
          );
        }
        if (command.title != null) _requireTitle(command.title!);
        if (command.content != null) {
          _requireMax(
            value: command.content!,
            max: ResourceLimits.maxPartCharacters,
            field: 'content',
          );
        }
      case MovePartCommand():
        _requireToken(command.expectedUpdatedAt);
        _requireIndex(command.targetIndex, 'targetIndex');
      case DeletePartCommand():
        _requireToken(command.expectedUpdatedAt);
      case RegenerateSectionCommand():
        _requireMax(
          value: command.instruction,
          max: maxInstructionLength,
          field: 'instruction',
        );
    }
  }

  static void _requireTitle(String title) {
    if (title.trim().isEmpty) {
      throw const ResourceEditCommandException(
        message: '标题不能为空',
        field: 'title',
      );
    }
    _requireMax(value: title, max: maxTitleLength, field: 'title');
  }

  static void _requireToken(String expectedUpdatedAt) {
    if (expectedUpdatedAt.isEmpty) {
      throw const ResourceEditCommandException(
        message: '缺少 expectedUpdatedAt 乐观锁令牌',
        field: 'expectedUpdatedAt',
      );
    }
  }

  static void _requireIndex(int index, String field) {
    if (index < 0) {
      throw ResourceEditCommandException(
        message: '$field 不能为负数',
        field: field,
      );
    }
  }

  static void _requireMax({
    required String value,
    required int max,
    required String field,
  }) {
    if (value.length > max) {
      throw ResourceEditCommandException(
        message: '$field 长度 ${value.length} 超出上限 $max',
        field: field,
      );
    }
  }
}
