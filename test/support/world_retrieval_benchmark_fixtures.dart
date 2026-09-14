import 'package:lt_dialogue/application/narrative/narrative_context.dart';
import 'package:lt_dialogue/models/world_entry.dart';
import 'package:lt_dialogue/utils/token_estimator.dart';

/// Categories required by the P1 World Context Retrieval Quality Audit.
enum RetrievalBenchmarkCategory {
  exactKeyword,
  reorderedKeywords,
  synonymousPhrasing,
  indirectDescription,
  locationRelevance,
  characterRelevance,
  stickyConstraint,
  factLoreCompetition,
  irrelevantContent,
  similarDistractor,
  aliasesAndAbbreviations,
  chineseLinguisticVariation,
}

extension RetrievalBenchmarkCategoryExt on RetrievalBenchmarkCategory {
  String get displayName => switch (this) {
        RetrievalBenchmarkCategory.exactKeyword => '1. 精确关键词',
        RetrievalBenchmarkCategory.reorderedKeywords => '2. 关键词重组',
        RetrievalBenchmarkCategory.synonymousPhrasing => '3. 同义表达',
        RetrievalBenchmarkCategory.indirectDescription => '4. 间接描述',
        RetrievalBenchmarkCategory.locationRelevance => '5. 地点关联',
        RetrievalBenchmarkCategory.characterRelevance => '6. 角色关联',
        RetrievalBenchmarkCategory.stickyConstraint => '7. Sticky / Constraint',
        RetrievalBenchmarkCategory.factLoreCompetition => '8. Fact / Lore 竞争',
        RetrievalBenchmarkCategory.irrelevantContent => '9. 无关内容',
        RetrievalBenchmarkCategory.similarDistractor => '10. 相似但错误',
        RetrievalBenchmarkCategory.aliasesAndAbbreviations => '11. 别名/简称',
        RetrievalBenchmarkCategory.chineseLinguisticVariation => '12. 中文表达变化',
      };
}

/// Root-cause taxonomy for retrieval failures.
enum RetrievalFailureReason {
  missingKeys,
  substringMismatchSynonym,
  locationMismatch,
  characterMetadataMissing,
  scoreRankingIssue,
  tokenBudgetEviction,
  duplicateNormalizationLoss,
  classificationMismatch,
  testDataMetadataIncomplete,
}

extension RetrievalFailureReasonExt on RetrievalFailureReason {
  String get description => switch (this) {
        RetrievalFailureReason.missingKeys => 'key 缺失',
        RetrievalFailureReason.substringMismatchSynonym =>
          'contains 机制无法理解同义/语义表达',
        RetrievalFailureReason.locationMismatch => 'location 未命中或层级不匹配',
        RetrievalFailureReason.characterMetadataMissing =>
          '角色仅在正文出现但缺少 character metadata/key',
        RetrievalFailureReason.scoreRankingIssue => 'score 排序导致低优先条目抢先',
        RetrievalFailureReason.tokenBudgetEviction => 'token budget 不足导致候选项被裁掉',
        RetrievalFailureReason.duplicateNormalizationLoss => 'normalize 导致错误去重',
        RetrievalFailureReason.classificationMismatch =>
          '分类 constraint/fact/lore 不准确',
        RetrievalFailureReason.testDataMetadataIncomplete =>
          '测试数据本身 metadata 不完整',
      };
}

enum RetrievalIssueType {
  algorithm,
  dataModeling,
}

extension RetrievalIssueTypeExt on RetrievalIssueType {
  String get label => switch (this) {
        RetrievalIssueType.algorithm => '检索算法问题',
        RetrievalIssueType.dataModeling => 'WorldEntry 数据建模问题',
      };
}

/// A deterministic benchmark test case for world retrieval quality evaluation.
final class WorldRetrievalTestCase {
  final String id;
  final RetrievalBenchmarkCategory category;
  final String description;
  final String query;
  final String location;
  final List<String> characterNames;
  final List<WorldEntry> entries;
  final int tokenBudget;
  final Set<int> expectedRelevantEntryIds;
  final Set<int> expectedIrrelevantEntryIds;
  final RetrievalFailureReason? expectedFailureReason;
  final RetrievalIssueType? expectedIssueType;
  final String notes;

  const WorldRetrievalTestCase({
    required this.id,
    required this.category,
    required this.description,
    required this.query,
    this.location = '',
    this.characterNames = const [],
    required this.entries,
    this.tokenBudget = 2048,
    required this.expectedRelevantEntryIds,
    this.expectedIrrelevantEntryIds = const {},
    this.expectedFailureReason,
    this.expectedIssueType,
    this.notes = '',
  });
}

/// Evaluation result of a single benchmark case.
final class TestCaseEvaluationResult {
  final WorldRetrievalTestCase testCase;
  final WorldRuntimeContext result;
  final Set<int> recalledEntryIds;
  final Set<int> truePositives;
  final Set<int> falseNegatives;
  final Set<int> falsePositives;
  final Set<int> trueNegatives;
  final int tokenWaste;
  final RetrievalFailureReason? identifiedFailureReason;
  final RetrievalIssueType? identifiedIssueType;

  const TestCaseEvaluationResult({
    required this.testCase,
    required this.result,
    required this.recalledEntryIds,
    required this.truePositives,
    required this.falseNegatives,
    required this.falsePositives,
    required this.trueNegatives,
    required this.tokenWaste,
    this.identifiedFailureReason,
    this.identifiedIssueType,
  });

  bool get isFullSuccess => falseNegatives.isEmpty && falsePositives.isEmpty;
  double get recall => (truePositives.length + falseNegatives.length) == 0
      ? 1.0
      : truePositives.length / (truePositives.length + falseNegatives.length);
  double get precision => (truePositives.length + falsePositives.length) == 0
      ? 1.0
      : truePositives.length / (truePositives.length + falsePositives.length);
}

/// Aggregate metrics across multiple benchmark cases.
final class AggregateRetrievalMetrics {
  final int totalCases;
  final int totalExpectedPositives;
  final int totalRecalled;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final int trueNegatives;
  final int totalTokenWaste;
  final double recall;
  final double precision;
  final double f1Score;
  final double constraintRetention;
  final double factRetention;
  final double loreNoise;
  final Map<RetrievalBenchmarkCategory, CategoryMetrics> categoryBreakdown;
  final Map<RetrievalFailureReason, int> failureReasonCounts;
  final Map<RetrievalIssueType, int> issueTypeCounts;

  const AggregateRetrievalMetrics({
    required this.totalCases,
    required this.totalExpectedPositives,
    required this.totalRecalled,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.trueNegatives,
    required this.totalTokenWaste,
    required this.recall,
    required this.precision,
    required this.f1Score,
    required this.constraintRetention,
    required this.factRetention,
    required this.loreNoise,
    required this.categoryBreakdown,
    required this.failureReasonCounts,
    required this.issueTypeCounts,
  });
}

final class CategoryMetrics {
  final int cases;
  final int tp;
  final int fp;
  final int fn;
  final int tn;
  final int tokenWaste;
  final double recall;
  final double precision;

  const CategoryMetrics({
    required this.cases,
    required this.tp,
    required this.fp,
    required this.fn,
    required this.tn,
    required this.tokenWaste,
    required this.recall,
    required this.precision,
  });
}

/// Evaluator runner for benchmark fixtures.
final class WorldRetrievalBenchmarkRunner {
  final WorldContextBuilder builder;

  const WorldRetrievalBenchmarkRunner({
    this.builder = const WorldContextBuilder(),
  });

  TestCaseEvaluationResult evaluate(WorldRetrievalTestCase testCase) {
    final result = builder.build(
      entries: testCase.entries,
      query: testCase.query,
      location: testCase.location,
      characterNames: testCase.characterNames,
      tokenBudget: testCase.tokenBudget,
    );

    final recalledIds = {
      for (final item in result.all)
        if (item.entryId != null) item.entryId!,
    };

    final tp = testCase.expectedRelevantEntryIds.intersection(recalledIds);
    final fn = testCase.expectedRelevantEntryIds.difference(recalledIds);
    final fp = recalledIds.difference(testCase.expectedRelevantEntryIds);
    final allIrrelevant = testCase.entries
        .map((e) => e.id ?? -1)
        .where((id) => !testCase.expectedRelevantEntryIds.contains(id))
        .toSet();
    final tn = allIrrelevant.difference(recalledIds);

    var waste = 0;
    for (final id in fp) {
      final entry = testCase.entries.firstWhere((e) => e.id == id);
      waste += TokenEstimator(entry.content).tokens;
    }

    RetrievalFailureReason? reason;
    RetrievalIssueType? issueType;
    if (fn.isNotEmpty || fp.isNotEmpty) {
      reason = testCase.expectedFailureReason;
      issueType = testCase.expectedIssueType;
    }

    return TestCaseEvaluationResult(
      testCase: testCase,
      result: result,
      recalledEntryIds: recalledIds,
      truePositives: tp,
      falseNegatives: fn,
      falsePositives: fp,
      trueNegatives: tn,
      tokenWaste: waste,
      identifiedFailureReason: reason,
      identifiedIssueType: issueType,
    );
  }

  AggregateRetrievalMetrics runSuite(List<WorldRetrievalTestCase> suite) {
    final evaluations = suite.map(evaluate).toList();

    var tp = 0;
    var fp = 0;
    var fn = 0;
    var tn = 0;
    var tokenWaste = 0;
    var totalExpectedPositives = 0;
    var totalRecalled = 0;

    var expectedConstraints = 0;
    var retainedConstraints = 0;
    var expectedFacts = 0;
    var retainedFacts = 0;
    var totalIncludedLore = 0;
    var irrelevantIncludedLore = 0;

    final catMap =
        <RetrievalBenchmarkCategory, List<TestCaseEvaluationResult>>{};
    final failureCounts = <RetrievalFailureReason, int>{};
    final issueCounts = <RetrievalIssueType, int>{};

    for (final eval in evaluations) {
      tp += eval.truePositives.length;
      fp += eval.falsePositives.length;
      fn += eval.falseNegatives.length;
      tn += eval.trueNegatives.length;
      tokenWaste += eval.tokenWaste;
      totalExpectedPositives += eval.testCase.expectedRelevantEntryIds.length;
      totalRecalled += eval.recalledEntryIds.length;

      catMap.putIfAbsent(eval.testCase.category, () => []).add(eval);

      if (eval.identifiedFailureReason != null) {
        failureCounts[eval.identifiedFailureReason!] =
            (failureCounts[eval.identifiedFailureReason!] ?? 0) + 1;
      }
      if (eval.identifiedIssueType != null) {
        issueCounts[eval.identifiedIssueType!] =
            (issueCounts[eval.identifiedIssueType!] ?? 0) + 1;
      }

      for (final entry in eval.testCase.entries) {
        final id = entry.id ?? -1;
        final isExpected = eval.testCase.expectedRelevantEntryIds.contains(id);
        final isRecalled = eval.recalledEntryIds.contains(id);

        if (entry.content.startsWith('【世界观/世界规则】') ||
            entry.sourceType == 'rule') {
          if (isExpected) {
            expectedConstraints++;
            if (isRecalled) retainedConstraints++;
          }
        } else if (entry.content.contains('【世界观/当前世界状态】') ||
            entry.content.contains('【世界观/locations】') ||
            entry.content.contains('【世界观/factions】') ||
            entry.sourceType == 'location' ||
            entry.sourceType == 'faction') {
          if (isExpected) {
            expectedFacts++;
            if (isRecalled) retainedFacts++;
          }
        } else {
          if (isRecalled) {
            totalIncludedLore++;
            if (!isExpected) {
              irrelevantIncludedLore++;
            }
          }
        }
      }
    }

    final recall = (tp + fn) == 0 ? 1.0 : tp / (tp + fn);
    final precision = (tp + fp) == 0 ? 1.0 : tp / (tp + fp);
    final f1 = (precision + recall) == 0
        ? 0.0
        : 2 * (precision * recall) / (precision + recall);

    final categoryBreakdown = <RetrievalBenchmarkCategory, CategoryMetrics>{};
    for (final entry in catMap.entries) {
      final list = entry.value;
      final cTp = list.fold<int>(0, (s, e) => s + e.truePositives.length);
      final cFp = list.fold<int>(0, (s, e) => s + e.falsePositives.length);
      final cFn = list.fold<int>(0, (s, e) => s + e.falseNegatives.length);
      final cTn = list.fold<int>(0, (s, e) => s + e.trueNegatives.length);
      final cWaste = list.fold<int>(0, (s, e) => s + e.tokenWaste);
      final cRecall = (cTp + cFn) == 0 ? 1.0 : cTp / (cTp + cFn);
      final cPrecision = (cTp + cFp) == 0 ? 1.0 : cTp / (cTp + cFp);

      categoryBreakdown[entry.key] = CategoryMetrics(
        cases: list.length,
        tp: cTp,
        fp: cFp,
        fn: cFn,
        tn: cTn,
        tokenWaste: cWaste,
        recall: cRecall,
        precision: cPrecision,
      );
    }

    return AggregateRetrievalMetrics(
      totalCases: suite.length,
      totalExpectedPositives: totalExpectedPositives,
      totalRecalled: totalRecalled,
      truePositives: tp,
      falsePositives: fp,
      falseNegatives: fn,
      trueNegatives: tn,
      totalTokenWaste: tokenWaste,
      recall: recall,
      precision: precision,
      f1Score: f1,
      constraintRetention: expectedConstraints == 0
          ? 1.0
          : retainedConstraints / expectedConstraints,
      factRetention: expectedFacts == 0 ? 1.0 : retainedFacts / expectedFacts,
      loreNoise: totalIncludedLore == 0
          ? 0.0
          : irrelevantIncludedLore / totalIncludedLore,
      categoryBreakdown: categoryBreakdown,
      failureReasonCounts: failureCounts,
      issueTypeCounts: issueCounts,
    );
  }
}

/// Benchmark fixture factory providing standard and adversarial test cases.
final class WorldRetrievalBenchmarkSuite {
  static List<WorldRetrievalTestCase> buildDefaultSuite() {
    return [
      // =======================================================================
      // 1. 精确关键词 (Exact keyword)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'exact_keyword_silvermoon_features',
        category: RetrievalBenchmarkCategory.exactKeyword,
        description: '精确关键词命中：查询包含完整关键词“银月城”',
        query: '银月城有什么特点？',
        entries: [
          WorldEntry(
            id: 101,
            keys: ['银月城', '北境', '魔法研究中心'],
            content: '【世界观/locations】银月城是北境最大的魔法研究中心。',
            sourceType: 'location',
          ),
          WorldEntry(
            id: 102,
            keys: ['铁岩堡', '矮人'],
            content: '【世界观/locations】铁岩堡是南方群山中的矮人工坊。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {101},
        expectedIrrelevantEntryIds: {102},
        notes: '必须精确召回。',
      ),
      WorldRetrievalTestCase(
        id: 'exact_keyword_faction_inquiry',
        category: RetrievalBenchmarkCategory.exactKeyword,
        description: '精确关键词命中：查询包含势力名“秘术议会”',
        query: '秘术议会的会长是谁？',
        entries: [
          WorldEntry(
            id: 103,
            keys: ['秘术议会', '大法师'],
            content: '【世界观/factions】秘术议会由七位高阶大法师共同掌管。',
            sourceType: 'faction',
          ),
          WorldEntry(
            id: 104,
            keys: ['血旗海盗', '黑礁岛'],
            content: '【世界观/factions】血旗海盗盘踞在黑礁岛周边海域。',
            sourceType: 'faction',
          ),
        ],
        expectedRelevantEntryIds: {103},
        expectedIrrelevantEntryIds: {104},
      ),

      // =======================================================================
      // 2. 关键词重组 (Reordered keywords)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'reordered_keywords_silvermoon_center',
        category: RetrievalBenchmarkCategory.reorderedKeywords,
        description: '关键词重组：多个分散关键词“北境”与“魔法研究中心”分别命中',
        query: '北境的魔法研究中心在哪里？',
        entries: [
          WorldEntry(
            id: 201,
            keys: ['银月城', '北境', '魔法研究中心'],
            content: '【世界观/locations】银月城是北境最大的魔法研究中心。',
            sourceType: 'location',
          ),
          WorldEntry(
            id: 202,
            keys: ['极北冰原', '古代遗迹'],
            content: '【世界观/locations】极北冰原深埋着第三纪元的遗迹。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {201},
        expectedIrrelevantEntryIds: {202},
        notes: '应召回（命中 2 个独立 keys）。',
      ),
      WorldRetrievalTestCase(
        id: 'reordered_keywords_reversed_syntax',
        category: RetrievalBenchmarkCategory.reorderedKeywords,
        description: '关键词重组：疑问词倒装与成分调序',
        query: '魔法研究中心最大的地方，是在北境吗？',
        entries: [
          WorldEntry(
            id: 203,
            keys: ['北境', '魔法研究中心', '银月城'],
            content: '【世界观/locations】银月城是北境最大的魔法研究中心。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {203},
      ),

      // =======================================================================
      // 3. 同义表达 (Synonymous phrasing)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'synonym_northern_spell_city',
        category: RetrievalBenchmarkCategory.synonymousPhrasing,
        description: '同义表达：“北方学习法术最厉害的城市” vs “北境魔法研究中心”',
        query: '我想去北方学习法术最厉害的城市。',
        entries: [
          WorldEntry(
            id: 301,
            keys: ['银月城', '北境', '魔法研究中心'],
            content: '【世界观/locations】银月城是北境最大的魔法研究中心。',
            sourceType: 'location',
          ),
          WorldEntry(
            id: 302,
            keys: ['极北冰原'],
            content: '【世界观/locations】极北冰原终年暴雪肆虐。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {301},
        expectedIrrelevantEntryIds: {302},
        expectedFailureReason: RetrievalFailureReason.substringMismatchSynonym,
        expectedIssueType: RetrievalIssueType.algorithm,
        notes: '当前 contains 算法无法识别同义词，必然漏召回（FN）。',
      ),
      WorldRetrievalTestCase(
        id: 'synonym_smuggling_black_goods',
        category: RetrievalBenchmarkCategory.synonymousPhrasing,
        description: '同义表达：“来路不正的黑货渠道” vs “地下走私与销赃”',
        query: '想搞点来路不正的黑货，去哪找门路？',
        entries: [
          WorldEntry(
            id: 303,
            keys: ['灰雀帮', '地下走私', '销赃据点'],
            content: '【世界观/factions】灰雀帮掌控着地下走私渠道与销赃据点。',
            sourceType: 'faction',
          ),
        ],
        expectedRelevantEntryIds: {303},
        expectedFailureReason: RetrievalFailureReason.substringMismatchSynonym,
        expectedIssueType: RetrievalIssueType.algorithm,
      ),

      // =======================================================================
      // 4. 间接描述 (Indirect description / semantic gaps)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'indirect_gathering_of_mages',
        category: RetrievalBenchmarkCategory.indirectDescription,
        description: '间接描述：“那个聚集大量法师学者的北方城市”',
        query: '那个聚集大量法师学者的北方城市情况如何？',
        entries: [
          WorldEntry(
            id: 401,
            keys: ['银月城', '北境', '魔法研究中心'],
            content: '【世界观/locations】银月城是北境最大的魔法研究中心。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {401},
        expectedFailureReason: RetrievalFailureReason.substringMismatchSynonym,
        expectedIssueType: RetrievalIssueType.algorithm,
        notes: '语义缺词，关键词无一重合。',
      ),
      WorldRetrievalTestCase(
        id: 'indirect_ancient_astronomy_spire',
        category: RetrievalBenchmarkCategory.indirectDescription,
        description: '间接描述：“能用肉眼俯瞰星辰轨迹的云端建筑” vs “苍穹之塔”',
        query: '听说这里有一座能用肉眼俯瞰星辰轨迹的云端建筑。',
        entries: [
          WorldEntry(
            id: 402,
            keys: ['苍穹之塔', '观星者', '天文台'],
            content: '【世界观/locations】苍穹之塔直插云霄，是观星者观测星轨的圣地。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {402},
        expectedFailureReason: RetrievalFailureReason.substringMismatchSynonym,
        expectedIssueType: RetrievalIssueType.algorithm,
      ),

      // =======================================================================
      // 5. 地点关联 (Location relevance)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'location_relevance_scene_match',
        category: RetrievalBenchmarkCategory.locationRelevance,
        description: '地点关联：当前 sceneState.location 为白港，查询未提及地点',
        query: '港口今天风浪大吗？有什么新鲜事？',
        location: '白港',
        entries: [
          WorldEntry(
            id: 501,
            keys: ['白港', '码头', '商贸'],
            content: '【世界观/locations】白港是北海不冻港，往来商船繁多。',
            sourceType: 'location',
          ),
          WorldEntry(
            id: 502,
            keys: ['雾林', '瘴气'],
            content: '【世界观/locations】雾林弥漫着致命瘴气。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {501},
        expectedIrrelevantEntryIds: {502},
        notes: 'location 直接注入 searchText 并由 content.contains(location) 保障。',
      ),
      WorldRetrievalTestCase(
        id: 'location_sublocation_hierarchical_mismatch',
        category: RetrievalBenchmarkCategory.locationRelevance,
        description: '地点关联层级不匹配：scene location 为“白港外港码头”，entry 仅有“白港”',
        query: '这里的停泊费用是多少？',
        location: '白港外港码头',
        entries: [
          WorldEntry(
            id: 503,
            keys: ['码头管理处', '停泊税'],
            content: '【世界观/locations】在白港，所有外来船只必须向码头管理处缴纳停泊税。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {503},
        expectedFailureReason: RetrievalFailureReason.locationMismatch,
        expectedIssueType: RetrievalIssueType.algorithm,
        notes: 'entry.content.contains("白港外港码头") 返回 false，发生算法层级断裂。',
      ),

      // =======================================================================
      // 6. 角色关联 (Character relevance)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'character_relevance_with_key',
        category: RetrievalBenchmarkCategory.characterRelevance,
        description: '角色关联（keys 完备）：提到在场同伴“艾琳”，entry keys 包含“艾琳”',
        query: '你觉得艾琳刚才的举动可疑吗？',
        characterNames: ['主角', '艾琳'],
        entries: [
          WorldEntry(
            id: 601,
            keys: ['艾琳', '暗影卫队', '刺客'],
            content: '【世界观/factions】暗影卫队曾收留并培养了刺客艾琳。',
            sourceType: 'faction',
          ),
          WorldEntry(
            id: 602,
            keys: ['鲍里斯', '铁匠'],
            content: '【世界观/factions】铁匠鲍里斯以锻造重铠闻名。',
            sourceType: 'faction',
          ),
        ],
        expectedRelevantEntryIds: {601},
        expectedIrrelevantEntryIds: {602},
      ),
      WorldRetrievalTestCase(
        id: 'character_relevance_missing_metadata_key',
        category: RetrievalBenchmarkCategory.characterRelevance,
        description: '角色关联（keys 缺失）：正文提及角色艾琳，但 keys 遗漏该角色名',
        query: '艾琳刚才露出的手腕刺青代表什么？',
        characterNames: ['主角', '艾琳'],
        entries: [
          WorldEntry(
            id: 603,
            keys: ['三头蛇印记', '暗杀组织'],
            content: '【世界观/factions】三头蛇暗杀组织的所有杀手（包括艾琳在内）都在右腕纹有黑蛇印记。',
            sourceType: 'faction',
          ),
        ],
        expectedRelevantEntryIds: {603},
        expectedFailureReason: RetrievalFailureReason.characterMetadataMissing,
        expectedIssueType: RetrievalIssueType.dataModeling,
        notes: 'WorldContextBuilder 仅在 keys 中检索 characterNames，不扫正文，导致漏召回。',
      ),

      // =======================================================================
      // 7. Sticky / Constraint
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'sticky_constraint_under_severe_budget_pressure',
        category: RetrievalBenchmarkCategory.stickyConstraint,
        description: 'Sticky 硬规则在极度紧张 token 预算下必须免过滤保留',
        query: '我拔剑斩向神像。',
        tokenBudget: 128,
        entries: [
          WorldEntry(
            id: 701,
            keys: ['世界规则', '神明'],
            content: '【世界观/世界规则】凡人不得亵渎神明真身，违者当场神罚天降。',
            sticky: 1,
            sourceType: 'rule',
          ),
          WorldEntry(
            id: 702,
            keys: ['神像', '祭坛'],
            content: '【世界观/locations】古老的神像由大理石雕刻而成，底座刻满了繁复符文，散发着微弱的光芒。' * 5,
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {701},
        expectedIrrelevantEntryIds: {702},
        notes: '规则条目必须享有 1000 基础分且豁免 token budget 裁剪。',
      ),
      WorldRetrievalTestCase(
        id: 'sticky_creative_constraints_vulnerable_classification',
        category: RetrievalBenchmarkCategory.stickyConstraint,
        description: '创作约束分类漏洞测试：创作约束虽为 sticky 但被归为 lore，高压下被裁',
        query: '我要召唤一只机械巨兽毁灭城市。',
        tokenBudget: 90,
        entries: [
          WorldEntry(
            id: 703,
            keys: ['创作约束', '机械'],
            content: '【世界观/创作约束】本世界观为纯低魔中世纪，禁止出现任何蒸汽或高科技机械。' * 2,
            sticky: 1,
            sourceType: 'worldview_snapshot',
          ),
          WorldEntry(
            id: 704,
            keys: ['城市', '防卫'],
            content: '【世界观/当前世界状态】帝国北部城市防卫严密，城门常年有重装卫兵把守，巡逻队日夜不休。' * 2,
            sticky: 1,
            sourceType: 'worldview_snapshot',
          ),
        ],
        expectedRelevantEntryIds: {703, 704},
        expectedFailureReason: RetrievalFailureReason.classificationMismatch,
        expectedIssueType: RetrievalIssueType.dataModeling,
        notes: '【世界观/创作约束】因缺少 rule 识别被误划为 lore（100分），在 90 token 预算下被裁剪。',
      ),

      // =======================================================================
      // 8. Fact / Lore 竞争 (Fact vs Lore competition)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'fact_lore_budget_competition',
        category: RetrievalBenchmarkCategory.factLoreCompetition,
        description: '预算不足时，高权重 Fact (500) 必须优先于普通 Lore (100) 保留',
        query: '这附近有什么危险？',
        tokenBudget: 120,
        entries: [
          WorldEntry(
            id: 801,
            keys: ['危险', '驻军'],
            content:
                '【世界观/locations】黑石隘口被叛军占领，任何旅人靠近均会遭受无差别弓弩射击，防线极其严密，四周布满陷阱与哨塔。' *
                    3,
            sourceType: 'location',
          ),
          WorldEntry(
            id: 802,
            keys: ['危险', '传说'],
            content: '【世界观/customs】民间传说在黑石山谷的深处曾经栖息着一只爱讲谜语的火狐狸。' * 3,
            sourceType: 'lore',
          ),
        ],
        expectedRelevantEntryIds: {801},
        expectedIrrelevantEntryIds: {802},
        notes: '801 (Fact 550分) 抢占预算，802 (Lore 150分) 因超预算被裁掉。',
      ),

      // =======================================================================
      // 9. 无关内容 (Irrelevant content - True Negatives)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'irrelevant_content_filtering',
        category: RetrievalBenchmarkCategory.irrelevantContent,
        description: '完全无关的日常指令不应误召回远古宏大背景',
        query: '我在酒馆吧台点了一杯麦酒，找了个角落坐下。',
        location: '白港旅馆',
        entries: [
          WorldEntry(
            id: 901,
            keys: ['古神', '深渊之门', '灭世'],
            content: '【世界观/timeline】两万年前，古神自深渊之门降临，撕裂了大陆核心。',
            sourceType: 'timeline',
          ),
          WorldEntry(
            id: 902,
            keys: ['炽阳神教', '教宗'],
            content: '【世界观/factions】炽阳神教的大教宗执掌至高裁判权。',
            sourceType: 'faction',
          ),
        ],
        expectedRelevantEntryIds: {},
        expectedIrrelevantEntryIds: {901, 902},
        notes: '两项均应判定为 irrelevant 并被过滤。',
      ),

      // =======================================================================
      // 10. 相似但错误 (Distractors / False Positives)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'distractor_similar_factions_isolation',
        category: RetrievalBenchmarkCategory.similarDistractor,
        description: '语义相近但事实完全不同的实体隔离：“暗月城”不应混入“银月城”',
        query: '银月城里的法师学派有哪些？',
        entries: [
          WorldEntry(
            id: 1001,
            keys: ['银月城', '法师学派', '象牙塔'],
            content: '【世界观/locations】银月城的象牙塔汇集了全大陆最好的元素法师。',
            sourceType: 'location',
          ),
          WorldEntry(
            id: 1002,
            keys: ['暗月城', '盗贼公会', '黑市'],
            content: '【世界观/locations】暗月城地处南部沼泽，是罪犯与黑市贩子的避难所。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {1001},
        expectedIrrelevantEntryIds: {1002},
      ),
      WorldRetrievalTestCase(
        id: 'distractor_overly_generic_key_pollution',
        category: RetrievalBenchmarkCategory.similarDistractor,
        description: '过度宽泛的通用 key（“城市”）导致无关条目污染 prompt',
        query: '银月城是怎样一座城市？',
        entries: [
          WorldEntry(
            id: 1003,
            keys: ['银月城'],
            content: '【世界观/locations】银月城是北境学术重镇。',
            sourceType: 'location',
          ),
          WorldEntry(
            id: 1004,
            keys: ['城市', '排污管网'],
            content: '【世界观/customs】南方城市常年受水浸困扰，排污管网错综复杂。',
            sourceType: 'customs',
          ),
        ],
        expectedRelevantEntryIds: {1003},
        expectedIrrelevantEntryIds: {1004},
        expectedFailureReason: RetrievalFailureReason.missingKeys,
        expectedIssueType: RetrievalIssueType.dataModeling,
        notes: '1004 使用了过于宽泛的 key "城市"，导致误召回（False Positive）。',
      ),

      // =======================================================================
      // 11. 别名/简称 (Aliases / Abbreviations)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'alias_unmapped_in_keys',
        category: RetrievalBenchmarkCategory.aliasesAndAbbreviations,
        description: '未在 keys 中建立别名映射：“帝都” vs “奥古斯都王都”',
        query: '帝都最近有什么大动静？',
        entries: [
          WorldEntry(
            id: 1101,
            keys: ['奥古斯都王都', '皇宫'],
            content: '【世界观/locations】奥古斯都王都（俗称帝都）近期正在筹备盛大的骑士比武。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {1101},
        expectedFailureReason: RetrievalFailureReason.missingKeys,
        expectedIssueType: RetrievalIssueType.dataModeling,
        notes: 'keys 缺少别名“帝都”，检索算法无法跨越代称。',
      ),
      WorldRetrievalTestCase(
        id: 'alias_properly_mapped_in_keys',
        category: RetrievalBenchmarkCategory.aliasesAndAbbreviations,
        description: 'metadata 正确建模别名：keys 补齐“帝都”、“王都”、“中央皇城”',
        query: '中央皇城防务归谁管辖？',
        entries: [
          WorldEntry(
            id: 1102,
            keys: ['奥古斯都王都', '帝都', '王都', '中央皇城', '禁卫军'],
            content: '【世界观/locations】奥古斯都王都防务由皇家第一禁卫军全权负责。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {1102},
        notes: '通过 metadata 建模解决别名问题。',
      ),

      // =======================================================================
      // 12. 中文表达变化 (Chinese linguistic variations)
      // =======================================================================
      WorldRetrievalTestCase(
        id: 'chinese_variation_omitted_subject',
        category: RetrievalBenchmarkCategory.chineseLinguisticVariation,
        description: '中文省略主语：“有什么禁忌吗？”（结合当前地点白港神殿）',
        query: '有什么禁忌吗？',
        location: '白港神殿',
        entries: [
          WorldEntry(
            id: 1201,
            keys: ['白港神殿', '潮汐之神', '禁忌'],
            content: '【世界观/locations】在白港神殿内，严禁携带带血的生铁武器入内。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {1201},
        notes: '由 location 关联补足主语缺失。',
      ),
      WorldRetrievalTestCase(
        id: 'chinese_variation_anaphora_pronoun',
        category: RetrievalBenchmarkCategory.chineseLinguisticVariation,
        description: '中文代词指代：“那里能买到施法材料吗？”（指代上文未进入 location 的地点）',
        query: '那里能买到施法材料吗？',
        entries: [
          WorldEntry(
            id: 1202,
            keys: ['红叶集市', '药草集散地'],
            content: '【世界观/locations】红叶集市是法术材料与药草的集散地。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {1202},
        expectedFailureReason: RetrievalFailureReason.substringMismatchSynonym,
        expectedIssueType: RetrievalIssueType.algorithm,
        notes: '纯代词“那里”无法命中“红叶集市”。',
      ),
      WorldRetrievalTestCase(
        id: 'chinese_variation_colloquialism',
        category: RetrievalBenchmarkCategory.chineseLinguisticVariation,
        description: '中文口语化表达：“上哪能整点防身用的硬家伙？”',
        query: '上哪能整点防身用的硬家伙？',
        entries: [
          WorldEntry(
            id: 1203,
            keys: ['矮人铁匠铺', '军备武器'],
            content: '【世界观/locations】矮人铁匠铺专门售卖精钢打造的军备武器与铠甲。',
            sourceType: 'location',
          ),
        ],
        expectedRelevantEntryIds: {1203},
        expectedFailureReason: RetrievalFailureReason.substringMismatchSynonym,
        expectedIssueType: RetrievalIssueType.algorithm,
        notes: '口语“整点硬家伙”与“军备武器”字面不匹配。',
      ),
      WorldRetrievalTestCase(
        id: 'chinese_variation_ultra_short_query',
        category: RetrievalBenchmarkCategory.chineseLinguisticVariation,
        description: '超短关键词查询：“规则”',
        query: '规则',
        entries: [
          WorldEntry(
            id: 1204,
            keys: ['规则', '世界规则'],
            content: '【世界观/世界规则】施展高环法术必须消耗灵魂碎屑。',
            sticky: 1,
            sourceType: 'rule',
          ),
        ],
        expectedRelevantEntryIds: {1204},
      ),
      WorldRetrievalTestCase(
        id: 'chinese_variation_long_narrative_query',
        category: RetrievalBenchmarkCategory.chineseLinguisticVariation,
        description: '长叙述查询：穿插环境描写、心理活动与长句提问',
        query:
            '狂风卷着细雪打在脸上，我缩紧脖子，低头穿过昏暗幽深的小巷，身后传来巡夜卫兵沉重的靴声。我警惕地拍了拍身旁的同伴，低声向他打听关于苍穹之塔的具体传闻。',
        entries: [
          WorldEntry(
            id: 1205,
            keys: ['苍穹之塔', '星轨'],
            content: '【世界观/locations】苍穹之塔是星象占卜的核心枢纽。',
            sourceType: 'location',
          ),
          WorldEntry(
            id: 1206,
            keys: ['巡夜卫兵', '宵禁条例'],
            content: '【世界观/customs】城市自子夜起执行严厉宵禁，巡夜卫兵有权拘捕一切闲逛人员。',
            sourceType: 'customs',
          ),
        ],
        expectedRelevantEntryIds: {1205, 1206},
        notes: '长文本同时命中两个独立实体，均应召回。',
      ),
    ];
  }
}
