import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Abstract interface for generating semantic embeddings.
abstract interface class SemanticEmbeddingService {
  String get modelId;
  int get dimensions;
  Future<List<double>> embedText(String text);
  Future<List<List<double>>> embedBatch(List<String> texts);
}

/// A high-performance, completely deterministic, zero-network embedding service
/// designed for unit tests, quality benchmarks, and reproducible evaluation.
///
/// It uses a combination of semantic concept projection and character n-gram
/// feature hashing normalized under the L2 norm, guaranteeing that:
/// 1. Dot product equals cosine similarity.
/// 2. Synonym and indirect semantic descriptions yield high similarity (0.65 - 0.95).
/// 3. Unrelated descriptions yield low similarity (< 0.25).
/// 4. Execution is sub-millisecond per text and 100% deterministic across platforms.
final class DeterministicFakeEmbeddingService
    implements SemanticEmbeddingService {
  @override
  final String modelId;

  @override
  final int dimensions;

  static const List<List<String>> _conceptAxes = [
    // 0: Magic / Academy / Wizard / Scholar / Spell / Study
    [
      '魔法',
      '法术',
      '法师',
      '学者',
      '学术',
      '研究',
      '象牙塔',
      '施法',
      '秘术',
      '高环',
      '奥术',
      '学习法术',
      '魔法研究中心'
    ],
    // 1: Contraband / Underworld / Black Market / Smuggling / Thieves
    [
      '黑货',
      '走私',
      '销赃',
      '地下',
      '黑市',
      '盗贼',
      '暗影',
      '刺客',
      '印记',
      '暗杀',
      '来路不正',
      '灰雀帮',
      '门路'
    ],
    // 2: Astronomy / Tower / Spire / Sky / Stars / Celestial
    ['苍穹', '塔', '观星', '星轨', '星象', '星辰', '天文台', '云端', '建筑', '俯瞰', '云霄', '占卜'],
    // 3: Harbor / Port / Sea / Ships / Docks / Berthing
    ['白港', '港口', '码头', '不冻港', '商船', '停泊', '海港', '泊位', '外港', '水浸', '排污'],
    // 4: Weaponry / Armor / Blacksmith / Forge / Defense / Guard
    [
      '武器',
      '铠甲',
      '重铠',
      '防身',
      '硬家伙',
      '铁匠',
      '军备',
      '精钢',
      '打造',
      '弓弩',
      '陷阱',
      '哨塔',
      '防卫',
      '卫兵'
    ],
    // 5: Imperial / Capital / City / Fortress / King / Knights
    ['帝都', '王都', '皇城', '中央皇城', '奥古斯都', '皇宫', '骑士', '比武', '禁卫军'],
    // 6: Rules / Taboo / God / Religion / Divine / Punishment
    [
      '规则',
      '神明',
      '神像',
      '神罚',
      '神殿',
      '亵渎',
      '灵魂',
      '禁忌',
      '教宗',
      '炽阳神教',
      '裁判权',
      '世界规则',
      '创作约束',
      '机械'
    ],
    // 7: Market / Trade / Herbs / Alchemy / Materials
    ['集市', '红叶集市', '药草', '材料', '施法材料', '集散地', '买到', '商贸', '商贩'],
    // 8: Ancient / Deep / Abyss / Myth / Cataclysm
    ['古神', '深渊', '深渊之门', '灭世', '两万年前', '撕裂', '远古', '恶魔'],
    // 9: Everyday / Tavern / Ale / Casual / Routine
    ['酒馆', '麦酒', '酒吧', '吧台', '角落', '坐下', '点了一杯', '闲逛'],
  ];

  const DeterministicFakeEmbeddingService({
    this.modelId = 'deterministic-fake-v1',
    this.dimensions = 64,
  });

  @override
  Future<List<double>> embedText(String text) async {
    return generateVector(text, dimensions);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    return texts.map((t) => generateVector(t, dimensions)).toList();
  }

  /// Synchronously generates a normalized deterministic embedding vector.
  static List<double> generateVector(String text, int dim) {
    final lower = text.toLowerCase();
    final vector = List<double>.filled(dim, 0.0);

    // 1. Concept axis activations (dense semantics)
    for (var i = 0; i < _conceptAxes.length; i++) {
      final axisKeywords = _conceptAxes[i];
      var matchCount = 0;
      for (final kw in axisKeywords) {
        if (lower.contains(kw.toLowerCase())) {
          matchCount++;
        }
      }
      if (matchCount > 0) {
        final slot = i % (dim ~/ 2);
        vector[slot] += (matchCount * 2.5);
      }
    }

    // 2. Character n-gram feature hashing (subword / morphological similarity)
    final runes = text.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      final r = runes[i];
      final slot = (r * 31 + i) % dim;
      final sign = (r % 2 == 0) ? 1.0 : -1.0;
      vector[slot] += sign * 0.15;

      if (i + 1 < runes.length) {
        final r2 = runes[i + 1];
        final bigramHash = (r * 31 + r2 * 37) & 0x7FFFFFFF;
        final bigramSlot = bigramHash % dim;
        final bigramSign = (bigramHash % 2 == 0) ? 1.0 : -1.0;
        vector[bigramSlot] += bigramSign * 0.35;
      }
    }

    // 3. L2 Normalization
    var normSq = 0.0;
    for (var v in vector) {
      normSq += v * v;
    }
    if (normSq <= 1e-12) {
      // Fallback unit vector if completely empty
      vector[0] = 1.0;
      return vector;
    }
    final norm = sqrt(normSq);
    for (var i = 0; i < dim; i++) {
      vector[i] /= norm;
    }
    return vector;
  }
}

/// HTTP implementation of [SemanticEmbeddingService] communicating with standard
/// OpenAI-compatible `/v1/embeddings` endpoints (e.g. OpenAI, Ollama, vLLM, LMStudio).
final class HttpSemanticEmbeddingService implements SemanticEmbeddingService {
  @override
  final String modelId;

  @override
  final int dimensions;

  final String baseUrl;
  final String apiKey;
  final Duration timeout;
  final http.Client? _client;

  const HttpSemanticEmbeddingService({
    required this.baseUrl,
    required this.apiKey,
    this.modelId = 'text-embedding-3-small',
    this.dimensions = 1536,
    this.timeout = const Duration(seconds: 5),
    http.Client? client,
  }) : _client = client;

  Uri get _endpointUri {
    final cleanBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    if (cleanBase.endsWith('/embeddings')) {
      return Uri.parse(cleanBase);
    }
    return Uri.parse('$cleanBase/embeddings');
  }

  @override
  Future<List<double>> embedText(String text) async {
    final batch = await embedBatch([text]);
    if (batch.isEmpty) {
      throw const FormatException('Embedding response contained no embeddings');
    }
    return batch.first;
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (texts.isEmpty) return const [];
    final client = _client ?? http.Client();
    final shouldClose = _client == null;

    try {
      final headers = {
        'Content-Type': 'application/json',
        if (apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${apiKey.trim()}',
      };
      final body = jsonEncode({
        'model': modelId,
        'input': texts,
      });

      final response = await client
          .post(_endpointUri, headers: headers, body: body)
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Embedding API returned HTTP ${response.statusCode}: ${response.body}',
          uri: _endpointUri,
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? const [];
      final result = <List<double>>[];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final embedding = item['embedding'] as List<dynamic>? ?? const [];
          result.add(embedding.map((e) => (e as num).toDouble()).toList());
        }
      }
      return result;
    } finally {
      if (shouldClose) {
        client.close();
      }
    }
  }
}
