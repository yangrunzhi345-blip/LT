import 'resource_contracts.dart';

/// Supported operations in the Incremental Patch Protocol for Part generation.
enum ResourcePatchOp {
  startPart('start_part'),
  appendText('append_text'),
  completePart('complete_part'),
  failPart('fail_part');

  const ResourcePatchOp(this.wireValue);

  final String wireValue;

  static ResourcePatchOp fromWire(String value) => switch (value) {
        'start_part' => startPart,
        'append_text' => appendText,
        'complete_part' => completePart,
        'fail_part' => failPart,
        _ => throw ArgumentError.value(value, 'value', '未知的 Patch 操作类型'),
      };
}

/// A single incremental patch unit for Part generation.
///
/// Cursor positions use Dart [String.length] UTF-16 code units. Model wire
/// patches normally omit [cursor]; the accumulator derives the authoritative
/// offset from accepted [textDelta] values. A non-null cursor is a legacy,
/// asserted position that must exactly match that application-derived offset.
///
/// Follows pure domain rules: no Flutter, no SQLite, no IO, and no
/// serialization methods on the entity.
final class ResourceGenerationPatch {
  const ResourceGenerationPatch({
    required this.protocolVersion,
    required this.generationId,
    required this.resourceId,
    required this.sectionId,
    required this.partId,
    required this.attemptId,
    required this.sequence,
    required this.op,
    this.textDelta = '',
    this.cursor,
    this.summary = '',
    this.errorMessage,
  })  : assert(protocolVersion == 1, '协议版本必须为 1'),
        assert(sequence >= 0, 'sequence 必须为非负整数'),
        assert(cursor == null || cursor >= 0, 'cursor 必须为非负整数');

  final int protocolVersion;
  final String generationId;
  final ResourceId resourceId;
  final SectionId sectionId;
  final PartId partId;
  final String attemptId;
  final int sequence;
  final ResourcePatchOp op;
  final String textDelta;

  /// Optional legacy assertion of the current UTF-16 cursor position.
  ///
  /// Omitted cursor values are deliberately not defaulted: the accumulator is
  /// the only authority that derives the position from accepted text.
  final int? cursor;
  final String summary;
  final String? errorMessage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResourceGenerationPatch &&
          runtimeType == other.runtimeType &&
          protocolVersion == other.protocolVersion &&
          generationId == other.generationId &&
          resourceId == other.resourceId &&
          sectionId == other.sectionId &&
          partId == other.partId &&
          attemptId == other.attemptId &&
          sequence == other.sequence &&
          op == other.op &&
          textDelta == other.textDelta &&
          cursor == other.cursor &&
          summary == other.summary &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
        protocolVersion,
        generationId,
        resourceId,
        sectionId,
        partId,
        attemptId,
        sequence,
        op,
        textDelta,
        cursor,
        summary,
        errorMessage,
      );

  @override
  String toString() =>
      'ResourceGenerationPatch(op: ${op.wireValue}, seq: $sequence, '
      'cursor: $cursor, deltaLen: ${textDelta.length}, part: ${partId.value})';
}
