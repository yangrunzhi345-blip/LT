import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/services/worldview_length_guard.dart';

void main() {
  const guard = WorldviewLengthGuard();

  group('WorldviewLengthGuard', () {
    test('should not count matching description and overview twice', () {
      final count = guard.count(
        detailJson: {
          'format_version': 2,
          'mode': 'detailed',
          'modules': {
            'overview': {'summary': '北境冰原', 'status': 'confirmed'},
          },
        },
        fallbackDescription: '北境冰原',
      );

      expect(count, '北境冰原'.length);
    });

    test('should exclude metadata and whitespace while counting visible text',
        () {
      final count = guard.count(detailJson: {
        'format_version': 2,
        'mode': 'detailed',
        'status': 'confirmed',
        'generation': {'source_hash': 'secret', 'question_index': 3},
        'modules': {
          'overview': {'summary': '中 文\nEnglish\t123', 'status': 'confirmed'},
          'world_rules': {'content': '法则。', 'status': 'confirmed'},
        },
      });

      expect(count, '中文English123法则。'.length);
    });

    test('should use description only when overview is absent', () {
      final count = guard.count(
        detailJson: {
          'modules': {
            'world_rules': {'content': '代价明确', 'status': 'confirmed'},
          },
        },
        fallbackDescription: '北境概述',
      );

      expect(count, '代价明确北境概述'.length);
    });
  });
}
