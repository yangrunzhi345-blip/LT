import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/resources/resource_contracts.dart';
import 'package:lt_dialogue/domain/resources/resource_limits.dart';
import 'package:lt_dialogue/services/repositories/resource_metadata_policy.dart';

/// F-3 decision: `metadata_json` gets structural validation plus a 64 KB cap.
/// These tests pin that decision so a later phase cannot quietly turn metadata
/// into a body container.
void main() {
  const policy = ResourceMetadataPolicy();

  group('ResourceMetadataPolicy accepts runtime core metadata', () {
    test('allows empty metadata', () {
      expect(
        () => policy.validate(
          type: ResourceType.worldview,
          metadata: const <String, Object?>{},
        ),
        returnsNormally,
      );
    });

    test('allows provenance, ids and short scalar fields', () {
      expect(
        () => policy.validate(
          type: ResourceType.character,
          metadata: const <String, Object?>{
            'authoring_method': 'aiReference',
            'ai_generation_depth': 'detailed',
            'origin_worldview_id': 'wv_123',
            'tags': ['玄幻', '学院'],
            'weight': 1.0,
            'is_public': true,
          },
        ),
        returnsNormally,
      );
    });

    test('allows a first-message sized runtime field', () {
      expect(
        () => policy.validate(
          type: ResourceType.character,
          metadata: <String, Object?>{
            'first_mes': 'x' * 1200,
            'system_prompt': 'y' * 1500,
          },
        ),
        returnsNormally,
      );
    });
  });

  group('ResourceMetadataPolicy rejects content containers', () {
    test('rejects a top-level body key', () {
      expect(
        () => policy.validate(
          type: ResourceType.worldview,
          metadata: <String, Object?>{'content': '整篇正文'},
        ),
        throwsA(isA<ResourceMetadataException>()),
      );
    });

    test('rejects a whole-tree mirror', () {
      expect(
        () => policy.validate(
          type: ResourceType.worldview,
          metadata: <String, Object?>{
            'sections': [
              {'title': 'a', 'parts': []},
            ],
          },
        ),
        throwsA(isA<ResourceMetadataException>()),
      );
      expect(
        () => policy.validate(
          type: ResourceType.worldview,
          metadata: <String, Object?>{
            'legacy': {
              'modules': {'overview': '旧模型镜像'},
            },
          },
        ),
        throwsA(isA<ResourceMetadataException>()),
      );
    });

    test('rejects separator and case variants of a banned key', () {
      for (final key in const [
        'content_json',
        'contentJson',
        'Content-Json',
        'FULL_CONTENT',
        'parts_json',
        'detail_json',
      ]) {
        expect(
          () => policy.validate(
            type: ResourceType.worldview,
            metadata: <String, Object?>{key: 'x'},
          ),
          throwsA(isA<ResourceMetadataException>()),
          reason: 'key "$key" must be rejected',
        );
      }
    });

    test('rejects a single string that fills the nominal budget', () {
      const nominal = ResourceLimits.characterNominalCharacters;
      expect(
        () => policy.validate(
          type: ResourceType.character,
          metadata: <String, Object?>{'body': 'x' * nominal},
        ),
        throwsA(isA<ResourceMetadataException>()),
      );
      // One character below the whole-card budget is still metadata-sized.
      expect(
        () => policy.validate(
          type: ResourceType.character,
          metadata: <String, Object?>{'body': 'x' * (nominal - 1)},
        ),
        returnsNormally,
      );
    });
  });

  group('ResourceMetadataPolicy enforces the size cap', () {
    test('rejects a payload above 64 KB', () {
      // Ten 4 KB fields stay under the cap...
      final justUnder = <String, Object?>{
        for (var i = 0; i < 10; i++) 'f$i': 'x' * 4000,
      };
      expect(
        () => policy.validate(
          type: ResourceType.worldview,
          metadata: justUnder,
        ),
        returnsNormally,
      );

      // ...while doubling the field count crosses it.
      final overCap = <String, Object?>{
        for (var i = 0; i < 20; i++) 'f$i': 'x' * 4000,
      };
      expect(
        () => policy.validate(
          type: ResourceType.worldview,
          metadata: overCap,
        ),
        throwsA(isA<ResourceMetadataException>()),
      );
    });

    test('rejects values that cannot be serialized', () {
      expect(
        () => policy.validate(
          type: ResourceType.worldview,
          metadata: <String, Object?>{'when': DateTime(2026, 9, 16)},
        ),
        throwsA(isA<ResourceMetadataException>()),
      );
    });
  });
}
