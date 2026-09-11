import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/models/llm_message.dart';

void main() {
  group('LlmMessage.toWireMap', () {
    test('text-only message keeps content as a String', () {
      final wire = LlmMessage.user('你好').toWireMap();
      expect(wire['role'], 'user');
      expect(wire['content'], '你好');
      expect(wire.containsKey('tool_calls'), isFalse);
      expect(wire.containsKey('tool_call_id'), isFalse);
    });

    test('image message emits an OpenAI content-block array', () {
      final wire = LlmMessage.userWithImages(
        images: [const LlmImagePart(base64: 'AAAA', mimeType: 'image/png')],
        text: '描述这张图',
      ).toWireMap();

      final content = wire['content'] as List;
      expect(content, hasLength(2));
      final image = content.first as Map<String, dynamic>;
      expect(image['type'], 'image_url');
      expect(
        (image['image_url'] as Map)['url'],
        'data:image/png;base64,AAAA',
      );
      final text = content.last as Map<String, dynamic>;
      expect(text, {'type': 'text', 'text': '描述这张图'});
    });

    test('image detail hint is forwarded when present', () {
      final wire = LlmMessage.userWithImages(
        images: [
          const LlmImagePart(base64: 'AAAA', detail: 'high'),
        ],
      ).toWireMap();
      final image = (wire['content'] as List).first as Map<String, dynamic>;
      expect((image['image_url'] as Map)['detail'], 'high');
    });

    test('assistant reasoning is omitted by default and opt-in when needed',
        () {
      final assistant = LlmMessage.assistant(
        text: '正文',
        reasoningContent: '思路',
      );
      expect(assistant.toWireMap().containsKey('reasoning_content'), isFalse);
      expect(
        assistant.toWireMap(includeReasoningContent: true)['reasoning_content'],
        '思路',
      );
    });

    test('tool calls round-trip on the wire', () {
      final wire = LlmMessage.assistant(
        toolCalls: const [
          LlmToolCall(id: 'call_1', name: 'lookup', argumentsJson: '{"q":1}'),
        ],
      ).toWireMap();
      final calls = wire['tool_calls'] as List;
      expect(calls, hasLength(1));
      final call = calls.first as Map<String, dynamic>;
      expect(call['id'], 'call_1');
      expect(call['type'], 'function');
      expect((call['function'] as Map)['name'], 'lookup');
      expect((call['function'] as Map)['arguments'], '{"q":1}');
    });

    test('tool result carries tool_call_id and role=tool', () {
      final wire = LlmMessage.toolResult(
        toolCallId: 'call_1',
        content: '{"ok":true}',
        name: 'lookup',
      ).toWireMap();
      expect(wire['role'], 'tool');
      expect(wire['tool_call_id'], 'call_1');
      expect(wire['content'], '{"ok":true}');
      expect(wire['name'], 'lookup');
    });
  });

  group('LlmMessageAdapter', () {
    test('legacy plain-text messages become text parts', () {
      final messages = LlmMessageAdapter.fromLegacy(const [
        {'role': 'system', 'content': '系统'},
        {'role': 'user', 'content': '你好'},
        {'role': 'assistant', 'content': '在'},
      ]);
      expect(messages, hasLength(3));
      expect(messages[0].role, LlmRole.system);
      expect(messages[1].role, LlmRole.user);
      expect(messages[2].role, LlmRole.assistant);
      expect(messages[1].joinedText, '你好');
    });

    test('legacy JSON-array content is decoded into typed parts', () {
      final legacy = [
        {
          'role': 'user',
          'content': jsonEncode([
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:image/jpeg;base64,AAAA',
                'detail': 'high',
              },
            },
            {'type': 'text', 'text': '描述'},
          ]),
        },
      ];

      final message = LlmMessageAdapter.fromLegacy(legacy).single;
      expect(message.hasImages, isTrue);
      expect(message.joinedText, '描述');
      final image = message.parts.whereType<LlmImagePart>().single;
      expect(image.base64, 'AAAA');
      expect(image.mimeType, 'image/jpeg');
      expect(image.detail, 'high');
      // Re-serializing yields the same array content the provider expects.
      expect(message.toWireMap()['content'], isA<List>());
    });

    test('non-JSON bracketed text is preserved verbatim', () {
      final message = LlmMessageAdapter.fromLegacy(const [
        {'role': 'user', 'content': '[不是JSON'},
      ]).single;
      expect(message.hasImages, isFalse);
      expect(message.joinedText, '[不是JSON');
    });

    test('toLegacy flattens to role/content strings', () {
      final legacy = LlmMessageAdapter.toLegacy([
        LlmMessage.system('系统'),
        LlmMessage.userWithImages(
          images: [const LlmImagePart(base64: 'AAAA')],
          text: '图片',
        ),
      ]);
      expect(legacy, [
        {'role': 'system', 'content': '系统'},
        {'role': 'user', 'content': '图片'},
      ]);
    });
  });
}
