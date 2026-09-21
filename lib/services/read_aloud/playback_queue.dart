import '../../domain/read_aloud/read_aloud_contracts.dart';
import 'text_segmenter.dart';
import 'text_sanitizer.dart';

/// 播放队列中的一个可朗读单元。
///
/// [sourceId] 保留该段来自哪个 Part / 消息，使“当前朗读段”可以映射回具体的
/// 资源节点（连续阅读的目录同步依赖它）。
class ReadAloudChunk {
  const ReadAloudChunk({
    required this.sourceId,
    required this.text,
    this.label,
  });

  final String sourceId;
  final String? label;
  final String text;
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
  static PlaybackQueue build({
    required List<ReadAloudSource> sources,
    required TextSanitizer sanitizer,
    required TextSegmenter segmenter,
  }) {
    final chunks = <ReadAloudChunk>[];
    for (final source in sources) {
      final clean = sanitizer.sanitize(source.text);
      if (clean.isEmpty) continue;
      for (final segment in segmenter.segment(clean)) {
        chunks.add(
          ReadAloudChunk(
            sourceId: source.id,
            label: source.label,
            text: segment,
          ),
        );
      }
    }
    return PlaybackQueue(chunks);
  }
}
