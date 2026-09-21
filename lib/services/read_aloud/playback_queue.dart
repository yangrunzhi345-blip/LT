import '../../domain/read_aloud/read_aloud_contracts.dart';
import 'language_tag.dart';
import 'read_aloud_language_detector.dart';
import 'text_segmenter.dart';
import 'text_sanitizer.dart';

/// 播放队列中的一个可朗读单元。
///
/// [sourceId] 保留该段来自哪个 Part / 消息，使“当前朗读段”可以映射回具体的
/// 资源节点（连续阅读的目录同步依赖它）。
///
/// [languageTag] 是该段**请求**的朗读语言（自动模式为检测结果，固定模式为
/// 用户配置语言）。真正的可用性解析由全局 Authority 结合系统能力完成，因此
/// 这里保存的是归一化后的 BCP-47 请求值，而不是最终生效值。
class ReadAloudChunk {
  const ReadAloudChunk({
    required this.sourceId,
    required this.text,
    required this.languageTag,
    this.label,
  });

  final String sourceId;
  final String? label;
  final String text;
  final String languageTag;
}

/// 扁平化的朗读队列：把多个来源清洗、分段后展开成顺序播放的段列表。
class PlaybackQueue {
  const PlaybackQueue(this._chunks);

  static const PlaybackQueue empty = PlaybackQueue(<ReadAloudChunk>[]);

  final List<ReadAloudChunk> _chunks;

  int get length => _chunks.length;
  bool get isEmpty => _chunks.isEmpty;

  ReadAloudChunk chunkAt(int index) => _chunks[index];

  /// 从原始来源构建队列。空正文与空白段会被丢弃，因此队列为空表示
  /// “没有可朗读的可见正文”。
  ///
  /// 语言解析流水线在这里落地（清洗 → 分段 → 语言 → Chunk）：
  /// - [ReadAloudLanguageMode.auto]：逐段调用 [detector] 检测，无法判断时用
  ///   [fixedLanguageTag] 兜底；分段器同时按语言边界断开，避免不同语言句子
  ///   被合并进同一段。
  /// - [ReadAloudLanguageMode.fixed]：所有段统一使用 [fixedLanguageTag]。
  static PlaybackQueue build({
    required List<ReadAloudSource> sources,
    required TextSanitizer sanitizer,
    required TextSegmenter segmenter,
    ReadAloudLanguageDetector detector = const ReadAloudLanguageDetector(),
    ReadAloudLanguageMode languageMode = ReadAloudLanguageMode.auto,
    String fixedLanguageTag = ReadAloudPreferences.defaultLanguageTag,
  }) {
    final fallbackTag = normalizeBcp47(fixedLanguageTag).isEmpty
        ? ReadAloudPreferences.defaultLanguageTag
        : normalizeBcp47(fixedLanguageTag);
    final isAuto = languageMode == ReadAloudLanguageMode.auto;
    final chunks = <ReadAloudChunk>[];
    for (final source in sources) {
      final clean = sanitizer.sanitize(source.text);
      if (clean.isEmpty) continue;
      final segments = segmenter.segment(
        clean,
        languageOf: isAuto
            ? (text) => detector.detect(text, fallback: fallbackTag)
            : null,
      );
      for (final segment in segments) {
        chunks.add(
          ReadAloudChunk(
            sourceId: source.id,
            label: source.label,
            text: segment,
            languageTag: isAuto
                ? detector.detect(segment, fallback: fallbackTag)
                : fallbackTag,
          ),
        );
      }
    }
    return PlaybackQueue(chunks);
  }
}
