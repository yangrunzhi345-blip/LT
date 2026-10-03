/// Shared paragraph boundaries and identities for automatic and manual reading.
///
/// Paragraph position, rather than its text, defines identity so repeated prose
/// can be highlighted and controlled independently.
class ReadAloudParagraphs {
  const ReadAloudParagraphs._();

  static String chunkIdFor(String sourceId, int index) => '$sourceId#p$index';

  static List<String> split(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const <String>[];
    return trimmed
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
  }
}
