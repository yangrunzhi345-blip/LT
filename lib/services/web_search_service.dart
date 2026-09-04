import 'dart:convert';
import 'package:http/http.dart' as http;

class WebSearchService {
  bool _isSearching = false;

  bool get isSearching => _isSearching;

  Future<List<SearchResult>> search(String query) async {
    _isSearching = true;
    try {
      final uri = Uri.https('api.duckduckgo.com', '', {
        'q': query,
        'format': 'json',
        'no_html': '1',
        'skip_disambig': '1',
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Search failed');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = <SearchResult>[];

      // Instant Answer
      if (data['AbstractText'] != null &&
          (data['AbstractText'] as String).isNotEmpty) {
        results.add(SearchResult(
          title: data['Heading'] as String? ?? '',
          snippet: data['AbstractText'] as String,
          source: data['AbstractSource'] as String? ?? 'DuckDuckGo',
          url: data['AbstractURL'] as String? ?? '',
        ));
      }

      // Related Topics
      final topics = data['RelatedTopics'] as List<dynamic>? ?? [];
      for (final t in topics.take(4)) {
        if (t is Map<String, dynamic>) {
          final text = t['Text'] as String?;
          if (text != null && text.isNotEmpty) {
            results.add(SearchResult(
              title: '',
              snippet: text,
              source: t['FirstURL'] as String? ?? '',
              url: t['FirstURL'] as String? ?? '',
            ));
          }
        }
      }

      return results.where((r) => r.snippet.isNotEmpty).toList();
    } catch (_) {
      return [];
    } finally {
      _isSearching = false;
    }
  }

  String formatForPrompt(List<SearchResult> results) {
    if (results.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('[网络搜索结果]');
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buf.writeln('${i + 1}. ${r.snippet}');
      if (r.source.isNotEmpty) buf.writeln('   来源: ${r.source}');
    }
    buf.writeln('[搜索结束 - 请在回复中参考以上信息]');
    return buf.toString();
  }
}

class SearchResult {
  final String title;
  final String snippet;
  final String source;
  final String url;

  const SearchResult({
    required this.title,
    required this.snippet,
    required this.source,
    required this.url,
  });
}
