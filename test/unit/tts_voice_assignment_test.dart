import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/domain/tts/stable_hash.dart';
import 'package:lt_dialogue/domain/tts/tts_models.dart';
import 'package:lt_dialogue/domain/tts/tts_voices.dart';
import 'package:lt_dialogue/services/tts/tts_voice_assignment.dart';

List<TtsVoiceDescriptor> _pool(int size) => <TtsVoiceDescriptor>[
      for (var i = 0; i < size; i++)
        TtsVoiceDescriptor(
          voiceId: 'family:s$i',
          voiceFamily: 'family',
          speakerId: i,
          displayName: 'speaker_$i',
          languages: const <String>['zh-CN'],
          capabilities: TtsVoiceCapabilities.kokoro,
        ),
    ];

void main() {
  const assignment = TtsVoiceAssignment();

  test('stableHash32 is deterministic across runs', () {
    expect(stableHash32('hello'), 0x4f9f2cab);
    expect(stableHash32('char-lin'), stableHash32('char-lin'));
    expect(stableHash32('char-lin'), isNot(stableHash32('char-chen')));
  });

  test('the same resource id always maps to the same voice', () {
    final pool = _pool(10);
    final a = assignment.assign('char-lin', pool);
    final b = assignment.assign('char-lin', pool);
    expect(a, b);
  });

  test('auto assignment is stable across plan composition when no collision',
      () {
    final pool = _pool(50);
    final single = assignment.assignForPlan(<String>['char-lin'], pool);
    final withOthers = assignment.assignForPlan(
      <String>['char-a', 'char-b', 'char-lin', 'char-c'],
      pool,
    );
    // With a large enough pool there is no collision, so the mapping matches
    // the plain deterministic hash.
    expect(withOthers['char-lin'], single['char-lin']);
  });

  test('co-occurring speakers avoid sharing a voice when the pool allows', () {
    final pool = _pool(4);
    final result = assignment.assignForPlan(<String>['a', 'b', 'c', 'd'], pool);
    expect(result.values.toSet(), hasLength(4));
  });

  test('an exhausted pool degrades gracefully without crashing', () {
    final pool = _pool(2);
    final result = assignment.assignForPlan(<String>['a', 'b', 'c'], pool);
    expect(result, hasLength(3));
    expect(result.values.every((v) => v.startsWith('family:s')), isTrue);
  });

  test('should handle one voice and the complete 103 voice pool', () {
    expect(assignment.assignForPlan(['a', 'b', 'c'], _pool(1)).values.toSet(),
        {'family:s0'});
    final speakers = List.generate(103, (i) => 'resource-$i');
    final result = assignment.assignForPlan(speakers, _pool(103));
    expect(result, hasLength(103));
    expect(result.values.toSet(), hasLength(103));
  });

  test('an empty pool yields no assignment', () {
    expect(assignment.assignForPlan(<String>['a'], <TtsVoiceDescriptor>[]),
        isEmpty);
    expect(assignment.assign('a', <TtsVoiceDescriptor>[]), isNull);
  });
}
