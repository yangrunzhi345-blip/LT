import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/adventure_response.dart';

void main() {
  group('AdventureResponse.rewritePayload', () {
    const prose = '她推开门，看向桌上的海图。';
    const options = ['查看海图', '询问船长', '整理行囊'];
    const snapshot = [
      {
        'id': 'inner_voice',
        'name': '心声',
        'value': '明日出航',
        'value_kind': 'text',
        'characterName': '林澈'
      },
    ];
    final payload = {
      'scene': '旅店',
      'options': options,
      'hp': 87,
      'energy': 63,
      'gold': 12,
      'inventory': ['海图'],
      'extension': {'revision': 4},
      'custom_status': [
        {'name': '伪造', 'value': '999'}
      ],
      'custom_attributes': [
        {'name': '旧别名', 'value': '999'}
      ],
      'custom_status_changes': [],
      'custom_status_evaluations': [],
    };
    final encoded = jsonEncode(payload);
    final shapes = {
      'canonical separator': '$prose\n---JSON---\n$encoded',
      'spaced separator': '$prose\n--- JSON ---\n$encoded',
      'newline separator': '$prose\n---\nJSON---\n$encoded',
      'inline tail': '$prose\n\n$encoded',
      'pure JSON with narrative': jsonEncode({
        ...payload,
        'narrative': [prose]
      }),
      'pure JSON payload only': encoded,
      'fenced JSON': '$prose\n---JSON---\n```json\n$encoded\n```',
      'repairable JSON':
          '$prose\n---JSON---\n${encoded.substring(0, encoded.length - 1)},}',
    };
    const removals = [
      'custom_status',
      'custom_attributes',
      'custom_status_changes',
      'custom_status_evaluations'
    ];

    for (final shape in shapes.entries) {
      for (final replaceOptions in [false, true]) {
        test(
            'should share parser acceptance for ${shape.key}, replacement=$replaceOptions',
            () {
          final before = AdventureResponse.parse(shape.value);
          expect(
              before.kind,
              anyOf(AdventureResponseKind.narrativeWithPayload,
                  AdventureResponseKind.payloadOnly));
          final result = AdventureResponse.rewritePayload(
            shape.value,
            defaults: const {'hp': 100},
            replacements: {
              'custom_status': snapshot,
              if (replaceOptions) 'options': options.reversed.toList()
            },
            removals: removals,
          );
          final after = AdventureResponse.parse(result);
          expect(after.kind, before.kind);
          expect(after.narrative, before.narrative);
          expect(after.payload!['options'],
              replaceOptions ? options.reversed.toList() : options);
          expect(after.payload!['custom_status'], snapshot);
          for (final key in [
            'scene',
            'hp',
            'energy',
            'gold',
            'inventory',
            'extension'
          ]) {
            expect(after.payload![key], payload[key]);
          }
          for (final key in removals.skip(1)) {
            expect(after.payload!.containsKey(key), isFalse);
          }
          expect(result, AdventureResponse.canonicalize(result));
          expect(AdventureResponse.llmHistoryProjection(result),
              before.narrative.join('\n\n'));
          expect(AdventureResponse.streamingDisplayText(result).trim(),
              before.narrative.join('\n\n'));
        });
      }
    }

    test('should leave plain prose without a synthetic empty payload', () {
      expect(AdventureResponse.rewritePayload(prose), prose);
    });
    test('should add local presentation to plain prose', () {
      final result = AdventureResponse.rewritePayload(prose,
          replacements: const {'options': options, 'custom_status': snapshot});
      final response = AdventureResponse.tryParseSplit(result)!;
      expect(response.narrative, [prose]);
      expect(response.options, options);
      expect(response.customStatus.single.value, '明日出航');
    });
    test('should remove untrusted status for an empty authoritative snapshot',
        () {
      final result = AdventureResponse.rewritePayload(shapes['inline tail']!,
          removals: removals);
      final response = AdventureResponse.tryParseSplit(result)!;
      expect(response.customStatus, isEmpty);
      expect(response.options, options);
      expect(response.narrative, [prose]);
    });
    test('should strip malformed JSON when repaired presentation is supplied',
        () {
      final result = AdventureResponse.rewritePayload(
          '$prose\n{"options":["broken',
          replacements: const {'options': options, 'custom_status': snapshot});
      final response = AdventureResponse.tryParseSplit(result)!;
      expect(response.narrative, [prose]);
      expect(response.options, options);
      expect(response.customStatus.single.value, '明日出航');
      expect(result, isNot(contains('broken')));
    });
    test('should not resurrect a payload after all its fields are removed', () {
      final content =
          '$prose\n---JSON---\n${jsonEncode({'custom_status': snapshot})}';
      final result =
          AdventureResponse.rewritePayload(content, removals: removals);
      expect(result, prose);
      expect(AdventureResponse.tryParseSplit(result), isNull);
      expect(
          AdventureResponse.rewritePayload(
              jsonEncode({'custom_status': snapshot}),
              removals: removals),
          isEmpty);
    });
    test('should neither mutate the input payload nor snapshot', () {
      final before = jsonEncode(snapshot);
      AdventureResponse.rewritePayload(encoded,
          replacements: const {'custom_status': snapshot}, removals: removals);
      expect(jsonEncode(snapshot), before);
      expect(payload['custom_status'], [
        {'name': '伪造', 'value': '999'}
      ]);
    });
  });
}
