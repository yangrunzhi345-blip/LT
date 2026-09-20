import 'dart:convert';

import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_contracts.dart';

/// Thrown when the LLM response or stored JSON cannot be parsed into a [ResourceBlueprint].
class BlueprintParseException implements Exception {
  const BlueprintParseException(this.message, {this.rawPayload = ''});

  final String message;
  final String rawPayload;

  @override
  String toString() => 'BlueprintParseException: $message';
}

/// Parser and serializer for [ResourceBlueprint].
abstract final class BlueprintParser {
  /// Parses the raw LLM completion output into a [ResourceBlueprint].
  static ResourceBlueprint parseLlmResponse({
    required String rawOutput,
    required String blueprintId,
    required String sessionId,
    required ResourceType resourceType,
    int revision = 1,
    String? fallbackName,
    int? targetCapacityOverride,
  }) {
    final cleanJson = extractJsonPayload(rawOutput);
    final dynamic decoded;
    try {
      decoded = jsonDecode(cleanJson);
    } catch (e) {
      throw BlueprintParseException(
        'LLM 返回的内容不是合法 JSON: $e',
        rawPayload: rawOutput,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw BlueprintParseException(
        'Blueprint JSON 顶层必须是 Object',
        rawPayload: rawOutput,
      );
    }

    return fromMap(
      decoded,
      blueprintId: blueprintId,
      sessionId: sessionId,
      resourceType: resourceType,
      revision: revision,
      fallbackName: fallbackName,
      targetCapacityOverride: targetCapacityOverride,
    );
  }

  /// Extracts JSON from raw text, removing markdown code blocks and wrapping text.
  static String extractJsonPayload(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      throw const BlueprintParseException('LLM 返回内容为空');
    }

    // Check for ```json ... ``` blocks
    final codeBlockMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(text);
    if (codeBlockMatch != null) {
      text = codeBlockMatch.group(1)!.trim();
    } else {
      // Find outermost { ... }
      final firstBrace = text.indexOf('{');
      final lastBrace = text.lastIndexOf('}');
      if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
        text = text.substring(firstBrace, lastBrace + 1).trim();
      }
    }

    return text;
  }

  /// Converts a parsed JSON Map into a [ResourceBlueprint].
  static ResourceBlueprint fromMap(
    Map<String, dynamic> map, {
    required String blueprintId,
    required String sessionId,
    required ResourceType resourceType,
    int revision = 1,
    BlueprintStatus status = BlueprintStatus.draft,
    String? fallbackName,
    ResourceId? resourceId,
    String createdAt = '',
    String updatedAt = '',
    int? targetCapacityOverride,
  }) {
    final suggestedName = (map['suggestedName'] as String?)?.trim() ??
        (map['name'] as String?)?.trim() ??
        fallbackName?.trim() ??
        '';
    final summary = (map['summary'] as String?)?.trim() ?? '';
    final targetCapacity =
        targetCapacityOverride ?? (map['targetCapacity'] as num?)?.toInt();

    final rawSections = map['sections'];
    if (rawSections is! List) {
      throw BlueprintParseException(
        'Blueprint 缺少 sections 数组字段',
        rawPayload: map.toString(),
      );
    }

    final sections = <BlueprintSection>[];
    for (var sIdx = 0; sIdx < rawSections.length; sIdx++) {
      final secItem = rawSections[sIdx];
      if (secItem is! Map<String, dynamic>) {
        throw BlueprintParseException(
            'Section 元素必须为 JSON Object (index $sIdx)');
      }

      final secId = (secItem['id'] as String?)?.trim() ?? '';
      final secTitle = (secItem['title'] as String?)?.trim() ?? '';
      final secSummary = (secItem['summary'] as String?)?.trim() ?? '';
      final secOrder = (secItem['sortOrder'] as num?)?.toInt() ?? sIdx;

      final rawParts = secItem['parts'];
      if (rawParts is! List) {
        throw BlueprintParseException('Section [$secId] 缺少 parts 数组字段');
      }

      final parts = <BlueprintPart>[];
      for (var pIdx = 0; pIdx < rawParts.length; pIdx++) {
        final partItem = rawParts[pIdx];
        if (partItem is! Map<String, dynamic>) {
          throw BlueprintParseException(
            'Part 元素必须为 JSON Object (section $secId, index $pIdx)',
          );
        }

        final partId = (partItem['id'] as String?)?.trim() ?? '';
        final partSectionId =
            (partItem['sectionId'] as String?)?.trim() ?? secId;
        final partTitle = (partItem['title'] as String?)?.trim() ?? '';
        final partGoal = (partItem['generationGoal'] as String?)?.trim() ??
            (partItem['goal'] as String?)?.trim() ??
            '';
        final partLength = (partItem['estimatedLength'] as num?)?.toInt() ??
            (partItem['length'] as num?)?.toInt() ??
            0;
        final partOrder = (partItem['sortOrder'] as num?)?.toInt() ?? pIdx;

        final rawDeps = partItem['dependencies'];
        final dependencies = <String>[];
        if (rawDeps is List) {
          for (final dep in rawDeps) {
            if (dep is String && dep.trim().isNotEmpty) {
              dependencies.add(dep.trim());
            }
          }
        }

        parts.add(BlueprintPart(
          id: partId,
          sectionId: partSectionId,
          title: partTitle,
          generationGoal: partGoal,
          estimatedLength: partLength,
          dependencies: dependencies,
          sortOrder: partOrder,
        ));
      }

      sections.add(BlueprintSection(
        id: secId,
        title: secTitle,
        summary: secSummary,
        sortOrder: secOrder,
        parts: parts,
      ));
    }

    return ResourceBlueprint(
      blueprintId: blueprintId,
      sessionId: sessionId,
      resourceType: resourceType,
      suggestedName: suggestedName,
      summary: summary,
      revision: revision,
      status: status,
      targetCapacity: targetCapacity,
      sections: sections,
      resourceId: resourceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Serializes a [ResourceBlueprint] to a JSON String for database persistence.
  static String serializeToJson(ResourceBlueprint blueprint) {
    final map = toMap(blueprint);
    return jsonEncode(map);
  }

  /// Deserializes a stored JSON String from database into [ResourceBlueprint].
  static ResourceBlueprint deserializeFromJson(
    String jsonStr, {
    required String blueprintId,
    required String sessionId,
    required ResourceType resourceType,
    int revision = 1,
    BlueprintStatus status = BlueprintStatus.draft,
    ResourceId? resourceId,
    String createdAt = '',
    String updatedAt = '',
  }) {
    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw const BlueprintParseException('存储的 Blueprint 数据不是合法 JSON Object');
    }
    return fromMap(
      decoded,
      blueprintId: blueprintId,
      sessionId: sessionId,
      resourceType: resourceType,
      revision: revision,
      status: status,
      resourceId: resourceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Converts a [ResourceBlueprint] into a Map for serialization.
  static Map<String, dynamic> toMap(ResourceBlueprint blueprint) {
    return {
      'blueprintId': blueprint.blueprintId,
      'sessionId': blueprint.sessionId,
      'resourceType': blueprint.resourceType.storageValue,
      'suggestedName': blueprint.suggestedName,
      'summary': blueprint.summary,
      'revision': blueprint.revision,
      'status': blueprint.status.storageValue,
      'targetCapacity': blueprint.targetCapacity,
      'resourceId': blueprint.resourceId?.value,
      'sections': blueprint.sections.map((sec) {
        return {
          'id': sec.id,
          'title': sec.title,
          'summary': sec.summary,
          'sortOrder': sec.sortOrder,
          'parts': sec.parts.map((p) {
            return {
              'id': p.id,
              'sectionId': p.sectionId,
              'title': p.title,
              'generationGoal': p.generationGoal,
              'estimatedLength': p.estimatedLength,
              'dependencies': p.dependencies,
              'sortOrder': p.sortOrder,
            };
          }).toList(),
        };
      }).toList(),
    };
  }
}
