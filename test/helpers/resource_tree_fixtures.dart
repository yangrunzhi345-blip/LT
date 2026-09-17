import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds a real resource tree through the production writer.
///
/// Phase 8 fixtures must go through `ResourceTreeRepositoryImpl` so capacity and
/// compression are measured against exactly the storage shape Phase 1 froze —
/// a hand-written INSERT could silently disagree with the real writer (content
/// hash, sort order, timestamps).
///
/// [sections] is one entry per Section, each holding that Section's Part bodies
/// in canonical order.
Future<ResourceId> createResourceTreeForTest(
  Database db, {
  required ResourceId id,
  required ResourceType type,
  required String name,
  required List<List<String>> sections,
  String summary = '',
}) {
  final repository = ResourceTreeRepositoryImpl(getDb: () async => db);
  return repository.createResourceTree(
    ResourceTreeDraft(
      id: id,
      type: type,
      name: name,
      summary: summary,
      sections: [
        for (var s = 0; s < sections.length; s++)
          ResourceTreeSectionDraft(
            title: '第$s章',
            parts: [
              for (var p = 0; p < sections[s].length; p++)
                ResourceTreePartDraft(
                  title: '部件$p',
                  content: sections[s][p],
                ),
            ],
          ),
      ],
    ),
  );
}

/// Reads the live Part bodies of one resource in canonical order.
///
/// Used to prove that compression never touches `resource_parts.content`.
Future<List<String>> readPartBodiesForTest(Database db, ResourceId id) async {
  final rows = await db.rawQuery(
    'SELECT p.content AS content FROM resource_parts p '
    'INNER JOIN resource_sections s ON s.id = p.section_id '
    'WHERE s.resource_id = ? AND p.deleted_at IS NULL AND s.deleted_at IS NULL '
    'ORDER BY s.sort_order, p.sort_order, p.id',
    [id.value],
  );
  return rows.map((row) => row['content']?.toString() ?? '').toList();
}
