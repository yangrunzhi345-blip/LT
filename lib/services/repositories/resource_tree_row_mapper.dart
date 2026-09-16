import 'dart:convert';

import '../../domain/resources/resource_contracts.dart';
import '../../utils/content_hasher.dart';
import 'resource_tree_repository.dart';

/// Maps `resources` / `resource_sections` / `resource_parts` rows onto the
/// Phase 0 domain entities.
///
/// Mapping lives in the repository layer on purpose: reading `metadata_json`
/// needs JSON decoding, and the contract layer must stay free of serialization.
/// Column names and storage strings therefore never leak into the domain.
abstract final class ResourceTreeRowMapper {
  static Resource resourceFromRow(Map<String, Object?> row) {
    return Resource(
      id: ResourceId(_requiredString(row, 'id')),
      type: _resourceType(row['type']),
      name: _string(row['name']),
      summary: _string(row['summary']),
      metadata: decodeMetadata(row['metadata_json']),
      status: _nodeStatus(row['status']),
    );
  }

  static ResourceSection sectionFromRow(Map<String, Object?> row) {
    return ResourceSection(
      id: SectionId(_requiredString(row, 'id')),
      resourceId: ResourceId(_requiredString(row, 'resource_id')),
      title: _string(row['title']),
      summary: _string(row['summary']),
      sortOrder: _int(row['sort_order']),
      status: _nodeStatus(row['status']),
    );
  }

  static ResourcePart partFromRow(Map<String, Object?> row) {
    return ResourcePart(
      id: PartId(_requiredString(row, 'id')),
      sectionId: SectionId(_requiredString(row, 'section_id')),
      title: _string(row['title']),
      content: _string(row['content']),
      sortOrder: _int(row['sort_order']),
      status: _nodeStatus(row['status']),
      contentHash: _string(row['content_hash']),
    );
  }

  /// Single source of the Part body hash rule.
  static String contentHashFor(String content) => ContentHasher.hash(content);

  static String encodeMetadata(Map<String, Object?> metadata) =>
      jsonEncode(metadata);

  static Map<String, Object?> decodeMetadata(Object? raw) {
    if (raw == null) return const <String, Object?>{};
    final text = raw.toString();
    if (text.trim().isEmpty) return const <String, Object?>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (error) {
      throw ResourceTreeCorruptedException('metadata_json 不是有效 JSON：$error');
    }
    if (decoded is! Map) {
      throw ResourceTreeCorruptedException(
        'metadata_json 必须是 JSON 对象，实际为 ${decoded.runtimeType}',
      );
    }
    return decoded.map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    );
  }

  static NodeStatus nodeStatusFromStorage(Object? raw) => _nodeStatus(raw);

  static ResourceType resourceTypeFromStorage(Object? raw) =>
      _resourceType(raw);

  static ResourceType _resourceType(Object? raw) {
    try {
      return ResourceType.fromStorageValue(raw?.toString());
    } on ResourceContractException catch (error) {
      throw ResourceTreeCorruptedException(error.message);
    }
  }

  static NodeStatus _nodeStatus(Object? raw) {
    final value = raw?.toString();
    for (final status in NodeStatus.values) {
      if (status.storageValue == value) return status;
    }
    throw ResourceTreeCorruptedException('未知节点状态：$value');
  }

  static String _requiredString(Map<String, Object?> row, String column) {
    final value = row[column]?.toString();
    if (value == null || value.isEmpty) {
      throw ResourceTreeCorruptedException('列 $column 缺失或为空');
    }
    return value;
  }

  static String _string(Object? raw) => raw?.toString() ?? '';

  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
