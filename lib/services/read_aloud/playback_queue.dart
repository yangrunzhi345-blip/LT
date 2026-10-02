import '../../domain/read_aloud/read_aloud_contracts.dart';
import '../../domain/tts/speech_plan.dart';
import 'language_tag.dart';
import 'read_aloud_language_detector.dart';
import 'text_segmenter.dart';
import 'text_sanitizer.dart';
import '../tts/speech_planner.dart';

/// 播放队列中的一个可朗读单元。
///
/// [sourceId] 保留该段来自哪个 Part / 消息，使“当前朗读段”可以映射回具体的
/// 资源节点（连续阅读的目录同步依赖它）。
///
/// [languageTag] 是该段**请求**的朗读语言（自动模式为检测结果，固定模式为
/// 用户配置语言）。真正的可用性解析由全局 Authority 结合系统能力完成，因此
/// 这里保存的是归一化后的 BCP-47 请求值，而不是最终生效值。
///
/// [role] 与 [speakerResourceId] 承载 speaker 规划结果：只有提供了结构化
/// SpeakerContext 时才会产生对白段；否则一律是旁白，保持既有行为。
class ReadAloudChunk {
  const ReadAloudChunk({
    required this.sourceId,
    required this.text,
    required this.languageTag,
    this.label,
    this.role = SpeechRole.narration,
    this.speakerResourceId,
  });

  final String sourceId;
  final String? label;
  final String text;
  final String languageTag;
  final SpeechRole role;
  final String? speakerResourceId;

  bool get isDialogue => role == SpeechRole.dialogue;
}

/// 扁平化的朗读队列：把多个来源清洗、分段后展开成顺序播放的段列表。
class PlaybackQueue {
  const PlaybackQueue(this._chunks);

  static const PlaybackQueue empty = PlaybackQueue(<ReadAloudChunk>[]);

  final List<ReadAloudChunk> _chunks;

  int get length => _chunks.length;
  bool get isEmpty => _chunks.isEmpty;

  ReadAloudChunk chunkAt(int index) => _chunks[index];

  /// 队列中出现过的对白说话人稳定资源 id（去重、保持顺序）。
  List<String> get speakerResourceIds {
    final ids = <String>[];
    for (final chunk in _chunks) {
      final id = chunk.speakerResourceId;
      if (chunk.isDialogue &&
          id != null &&
          id.isNotEmpty &&
          !ids.contains(id)) {
        ids.add(id);
      }
    }
    return ids;
  }

  /// 从原始来源构建队列。空正文与空白段会被丢弃，因此队列为空表示
  /// “没有可朗读的可见正文”。
  ///
  /// 语言解析流水线在这里落地（清洗 → 分段 → 语言 → Chunk）：
  /// - [ReadAloudLanguageMode.auto]：逐段调用 [detector] 检测，无法判断时用
  ///   [fixedLanguageTag] 兜底；分段器同时按语言边界断开，避免不同语言句子
  ///   被合并进同一段。
  /// - [ReadAloudLanguageMode.fixed]：所有段统一使用 [fixedLanguageTag]。
  ///
  /// Speaker 规划是**增量**能力：只有 [planner] 非空且某个来源带有非空
  /// [ReadAloudSource.speakerContext] 时才会拆出对白段；否则保持既有的整段旁白
  /// 行为，未提供上下文的旧调用方零回归。
  static PlaybackQueue build({
    required List<ReadAloudSource> sources,
    required TextSanitizer sanitizer,
    required TextSegmenter segmenter,
    ReadAloudLanguageDetector detector = const ReadAloudLanguageDetector(),
    ReadAloudLanguageMode languageMode = ReadAloudLanguageMode.auto,
    String fixedLanguageTag = ReadAloudPreferences.defaultLanguageTag,
    SpeechPlanner? planner,
  }) {
    final fallbackTag = normalizeBcp47(fixedLanguageTag).isEmpty
        ? ReadAloudPreferences.defaultLanguageTag
        : normalizeBcp47(fixedLanguageTag);
    final isAuto = languageMode == ReadAloudLanguageMode.auto;
    final chunks = <ReadAloudChunk>[];

    String detect(String text) =>
        isAuto ? detector.detect(text, fallback: fallbackTag) : fallbackTag;

    for (final source in sources) {
      final clean = sanitizer.sanitize(source.text);
      if (clean.isEmpty) continue;
      final context = source.speakerContext;
      final plan = (planner != null && !context.isEmpty)
          ? planner.plan(clean, context, idPrefix: source.id)
          : null;

      if (plan == null) {
        final segments = segmenter.segment(
          clean,
          languageOf: isAuto ? detect : null,
        );
        for (final segment in segments) {
          chunks.add(
            ReadAloudChunk(
              sourceId: source.id,
              label: source.label,
              text: segment,
              languageTag: detect(segment),
            ),
          );
        }
        continue;
      }

      for (final planned in plan.segments) {
        final segments = segmenter.segment(
          planned.text,
          languageOf: isAuto ? detect : null,
        );
        for (final segment in segments) {
          chunks.add(
            ReadAloudChunk(
              sourceId: source.id,
              label: source.label,
              text: segment,
              languageTag: detect(segment),
              role: planned.role,
              speakerResourceId: planned.speakerResourceId,
            ),
          );
        }
      }
    }
    return PlaybackQueue(chunks);
  }
}
