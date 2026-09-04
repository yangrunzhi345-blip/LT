import 'dart:math' as math;

import '../core/config/generation_limits.dart';
import '../utils/content_hasher.dart';

/// A deterministic, bounded unit of detailed-worldview generation.
class DetailedWorldviewQuestion {
  final int questionIndex;
  final int totalQuestions;
  final String module;
  final List<String> modules;
  final int part;
  final int totalParts;
  final int targetCharacters;
  final int maximumCharacters;
  final bool dependsOnPreviousPart;

  const DetailedWorldviewQuestion({
    required this.questionIndex,
    required this.totalQuestions,
    required this.module,
    required this.modules,
    required this.part,
    required this.totalParts,
    required this.targetCharacters,
    required this.maximumCharacters,
    required this.dependsOnPreviousPart,
  });

  String get id => '$module.part_$part';

  factory DetailedWorldviewQuestion.fromJson(Map<String, dynamic> json) =>
      DetailedWorldviewQuestion(
        questionIndex: (json['question_index'] as num?)?.toInt() ?? 0,
        totalQuestions: (json['total_questions'] as num?)?.toInt() ?? 0,
        module: json['module']?.toString() ?? '',
        modules: (json['modules'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
        part: (json['part'] as num?)?.toInt() ?? 0,
        totalParts: (json['total_parts'] as num?)?.toInt() ?? 0,
        targetCharacters: (json['target_characters'] as num?)?.toInt() ?? 0,
        maximumCharacters: (json['maximum_characters'] as num?)?.toInt() ?? 0,
        dependsOnPreviousPart: json['depends_on_previous_part'] == true,
      );

  Map<String, dynamic> toJson() => {
        'question_index': questionIndex,
        'total_questions': totalQuestions,
        'module': module,
        'modules': modules,
        'part': part,
        'total_parts': totalParts,
        'target_characters': targetCharacters,
        'maximum_characters': maximumCharacters,
        'depends_on_previous_part': dependsOnPreviousPart,
      };
}

class DetailedWorldviewGenerationProgress {
  final DetailedWorldviewQuestion question;
  final int completedQuestions;
  final String partialText;
  final bool questionCompleted;

  const DetailedWorldviewGenerationProgress({
    required this.question,
    required this.completedQuestions,
    required this.partialText,
    this.questionCompleted = false,
  });

  double get fraction =>
      (completedQuestions + (questionCompleted ? 1 : 0)) /
      question.totalQuestions;
}

/// Plans enough small questions that even a short worldview is clarified in
/// multiple passes, while larger targets receive monotonically more passes.
class DetailedWorldviewQuestionPlanner {
  static const modules = <String>[
    'overview',
    'world_rules',
    'world_state',
    'locations',
    'factions',
    'customs_and_life',
    'timeline',
    'glossary',
    'creative_constraints',
  ];

  const DetailedWorldviewQuestionPlanner();

  List<DetailedWorldviewQuestion> plan({
    required int targetTotalCharacters,
    int safeCharactersPerQuestion = 900,
  }) {
    final target = targetTotalCharacters
        .clamp(
          GenerationLimits.detailedWorldviewMinimumCharacters,
          GenerationLimits.detailedWorldviewMaximumCharacters,
        )
        .toInt();
    final safe = safeCharactersPerQuestion.clamp(250, 1800).toInt();
    final range = _rangeFor(target);
    final ratio = (target - range.$1) / (range.$2 - range.$1).clamp(1, 50000);
    final interpolated = range.$3 + ((range.$4 - range.$3) * ratio).round();
    final calculated = (target / safe).ceil();
    final count = math
        .max(
            range.$3,
            math.min(
                range.$4,
                math.max(
                  interpolated,
                  calculated,
                )))
        .toInt();

    final groups = _partition(count);
    final targetPerQuestion = (target / count).ceil();
    final occurrences = <String, int>{};
    final totals = <String, int>{};
    for (final group in groups) {
      for (final module in group) {
        totals[module] = (totals[module] ?? 0) + 1;
      }
    }
    return [
      for (var index = 0; index < groups.length; index++)
        () {
          final group = groups[index];
          final primary = group.first;
          final part = (occurrences[primary] ?? 0) + 1;
          occurrences[primary] = part;
          return DetailedWorldviewQuestion(
            questionIndex: index + 1,
            totalQuestions: count,
            module: primary,
            modules: List.unmodifiable(group),
            part: part,
            totalParts: totals[primary]!,
            targetCharacters: targetPerQuestion,
            maximumCharacters: (targetPerQuestion * 1.35).ceil(),
            dependsOnPreviousPart: part > 1,
          );
        }(),
    ];
  }

  (int, int, int, int) _rangeFor(int target) {
    if (target <= 5000) return (1000, 5000, 5, 7);
    if (target <= 10000) return (5001, 10000, 8, 13);
    if (target <= 20000) return (10001, 20000, 14, 21);
    if (target <= 30000) return (20001, 30000, 22, 30);
    return (30001, 50000, 31, 42);
  }

  List<List<String>> _partition(int count) {
    if (count <= modules.length) {
      final result = <List<String>>[];
      var cursor = 0;
      for (var index = 0; index < count; index++) {
        final remainingModules = modules.length - cursor;
        final remainingGroups = count - index;
        final size = (remainingModules / remainingGroups).ceil();
        result.add(List.unmodifiable(
            modules.sublist(cursor, math.min(modules.length, cursor + size))));
        cursor += size;
      }
      return result;
    }

    final result = <List<String>>[
      for (final module in modules) [module],
    ];
    final extraModules = [
      'world_rules',
      'world_state',
      'locations',
      'factions',
      'customs_and_life',
      'timeline',
      'glossary',
      'creative_constraints',
      'overview',
    ];
    for (var index = 0; result.length < count; index++) {
      result.add([extraModules[index % extraModules.length]]);
    }
    return result;
  }
}

typedef DetailedWorldviewQuestionExecutor = Future<Map<String, dynamic>>
    Function(DetailedWorldviewQuestion question);

/// Executes planned questions and assembles only validated question results.
/// Checkpoints are caller-owned so this coordinator works with both tests and
/// the existing Runtime persistence without forcing a schema migration.
class DetailedWorldviewGenerationCoordinator {
  final DetailedWorldviewQuestionPlanner planner;
  final int maxRetriesPerQuestion;
  final int maxConcurrentQuestions;

  const DetailedWorldviewGenerationCoordinator({
    this.planner = const DetailedWorldviewQuestionPlanner(),
    this.maxRetriesPerQuestion =
        GenerationLimits.detailedWorldviewRetriesPerQuestion,
    this.maxConcurrentQuestions =
        GenerationLimits.detailedWorldviewConcurrentQuestions,
  });

  Future<Map<String, dynamic>> generate({
    required String sourceText,
    required int targetTotalCharacters,
    required DetailedWorldviewQuestionExecutor executeQuestion,
    Map<int, Map<String, dynamic>> completed = const {},
    Future<void> Function(Map<String, dynamic> checkpoint)? onCheckpoint,
    bool Function()? isCancelled,
    void Function(DetailedWorldviewGenerationProgress progress)? onProgress,
  }) async {
    final target = targetTotalCharacters
        .clamp(
          GenerationLimits.detailedWorldviewMinimumCharacters,
          GenerationLimits.detailedWorldviewMaximumCharacters,
        )
        .toInt();
    final sourceHash = ContentHasher.hashString(sourceText);
    final questions = planner.plan(targetTotalCharacters: target);
    final answers = <int, Map<String, dynamic>>{};
    final questionsByIndex = {
      for (final question in questions) question.questionIndex: question,
    };
    for (final entry in completed.entries) {
      final question = questionsByIndex[entry.key];
      if (question == null) continue;
      try {
        _validateAnswer(question, entry.value);
        answers[entry.key] = entry.value;
      } on FormatException {
        // Keep the invalid row in durable storage for audit. It is excluded
        // from this deterministic plan so only this question is asked again.
      }
    }

    while (answers.length < questions.length) {
      if (isCancelled?.call() == true) {
        throw const DetailedWorldviewGenerationCancelled();
      }
      final ready = questions
          .where((question) {
            if (answers.containsKey(question.questionIndex)) return false;
            if (!question.dependsOnPreviousPart) return true;
            return answers.keys.any((index) {
              final previous =
                  questions.firstWhere((item) => item.questionIndex == index);
              return previous.module == question.module &&
                  previous.part == question.part - 1;
            });
          })
          .take(maxConcurrentQuestions.clamp(1, 6))
          .toList();
      if (ready.isEmpty) {
        throw StateError('详细世界观问题依赖未完成，不能继续生成。');
      }
      for (final question in ready) {
        onProgress?.call(DetailedWorldviewGenerationProgress(
          question: question,
          completedQuestions: answers.length,
          partialText: '',
        ));
      }

      final outcomes = await Future.wait(ready.map((question) async {
        Object? lastError;
        for (var attempt = 0; attempt < maxRetriesPerQuestion; attempt++) {
          try {
            final candidate = await executeQuestion(question);
            _validateAnswer(question, candidate);
            return (question: question, answer: candidate, error: null);
          } catch (error) {
            lastError = error;
          }
        }
        return (question: question, answer: null, error: lastError);
      }));

      Object? firstError;
      for (final outcome in outcomes) {
        if (outcome.answer == null) {
          firstError ??= outcome.error ?? StateError('问题执行失败');
          continue;
        }
        final answer = outcome.answer!;
        answers[outcome.question.questionIndex] = answer;
        await onCheckpoint?.call({
          'source_hash': sourceHash,
          'target_total_characters': target,
          'question': outcome.question.toJson(),
          'answer': answer,
        });
        onProgress?.call(DetailedWorldviewGenerationProgress(
          question: outcome.question,
          completedQuestions: answers.length - 1,
          partialText: _previewText(answer),
          questionCompleted: true,
        ));
      }
      if (firstError != null) throw firstError;
    }

    if (answers.length < questions.length) {
      throw StateError('详细世界观问题不完整，不能组装。');
    }
    return _assemble(questions, answers, sourceHash, target);
  }

  void _validateAnswer(
      DetailedWorldviewQuestion question, Map<String, dynamic> answer) {
    if (answer['question_index'] != question.questionIndex ||
        answer['total_questions'] != question.totalQuestions ||
        answer['part'] != question.part ||
        answer['total_parts'] != question.totalParts ||
        answer['status'] != 'confirmed' ||
        answer['content'] is! Map<String, dynamic>) {
      throw const FormatException('详细世界观问题响应不符合契约');
    }
    final module = answer['module']?.toString();
    if (module != question.module ||
        answersModuleIsDuplicate(answer, question) == false) {
      throw const FormatException('详细世界观问题模块或分片不匹配');
    }
    final content = answer['content'];
    final nested = content is Map ? content['modules'] : null;
    if (nested is! Map) {
      throw const FormatException('详细世界观问题模块内容为空');
    }
    for (final module in question.modules) {
      if (!_hasTextContent(nested[module])) {
        throw FormatException('详细世界观问题模块内容为空：$module');
      }
    }
  }

  bool _hasTextContent(dynamic value) {
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.any(_hasTextContent);
    if (value is Map) {
      return value.entries
          .where((entry) => entry.key.toString() != 'status')
          .any((entry) => _hasTextContent(entry.value));
    }
    return false;
  }

  bool answersModuleIsDuplicate(
      Map<String, dynamic> answer, DetailedWorldviewQuestion question) {
    final listed = answer['modules'];
    if (listed == null) return true;
    return listed is List &&
        listed
            .map((item) => item.toString())
            .toSet()
            .containsAll(question.modules);
  }

  Map<String, dynamic> _assemble(
    List<DetailedWorldviewQuestion> questions,
    Map<int, Map<String, dynamic>> answers,
    String sourceHash,
    int target,
  ) {
    final modules = <String, dynamic>{};
    String name = '';
    String description = '';
    for (final module in DetailedWorldviewQuestionPlanner.modules) {
      modules[module] = <String, dynamic>{
        'content': '',
        'status': 'draft',
      };
    }
    for (final question in questions) {
      final answer = answers[question.questionIndex]!;
      final content = Map<String, dynamic>.from(answer['content'] as Map);
      name = name.isEmpty ? content['name']?.toString() ?? '' : name;
      description = description.isEmpty
          ? content['description']?.toString() ?? ''
          : description;
      final nested = content['modules'];
      for (final module in question.modules) {
        final value = nested is Map && nested[module] != null
            ? nested[module]
            : content[module] ?? content['content'] ?? content;
        modules[module] = _mergeModule(modules[module], value);
      }
    }
    if (name.trim().isEmpty) name = 'AI 生成的世界观';
    if (description.trim().isEmpty) description = _summary(modules);
    final detailJson = {
      'format_version': 2,
      'mode': 'detailed',
      'modules': modules,
    };
    return {
      'name': name.trim(),
      'description': description.trim(),
      'detail_json': detailJson,
      'generation': {
        'source_hash': sourceHash,
        'target_total_characters': target,
        'total_questions': questions.length,
      },
    };
  }

  dynamic _mergeModule(dynamic previous, dynamic value) {
    if (value is Map) {
      return {
        ...Map<String, dynamic>.from(previous is Map ? previous : const {}),
        ...Map<String, dynamic>.from(value),
        'status': value['status'] ?? 'confirmed',
      };
    }
    return {'content': value, 'status': 'confirmed'};
  }

  String _summary(Map<String, dynamic> modules) {
    final values = modules.values
        .map((value) => value is Map ? value['content'] : value)
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .take(3);
    return values.join('\n');
  }

  String _previewText(Map<String, dynamic> answer) {
    final content = answer['content'];
    if (content is! Map) return '';
    final nested = content['modules'];
    if (nested is Map) {
      final text = nested.values
          .map((value) => value is Map ? value['content'] : value)
          .whereType<String>()
          .where((value) => value.trim().isNotEmpty)
          .join('\n');
      if (text.isNotEmpty) return text;
    }
    return content['description']?.toString() ?? '';
  }
}

class DetailedWorldviewGenerationCancelled implements Exception {
  const DetailedWorldviewGenerationCancelled();
}
