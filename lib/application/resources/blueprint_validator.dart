import '../../domain/resources/resource_blueprint.dart';
import '../../domain/resources/resource_limits.dart';

/// Base exception for all Blueprint validation failures.
class BlueprintValidationException implements Exception {
  const BlueprintValidationException(this.message, {this.field = ''});

  final String message;
  final String field;

  @override
  String toString() => 'BlueprintValidationException: $message';
}

/// Thrown when an ID in the blueprint is unauthorized, duplicated, or invalid.
class BlueprintIdException extends BlueprintValidationException {
  const BlueprintIdException(super.message, {super.field});
}

/// Thrown when the Part dependency graph contains a cycle or invalid edge.
class BlueprintDagCycleException extends BlueprintValidationException {
  const BlueprintDagCycleException(super.message, {this.cyclePath = const []})
      : super(field: 'dependencies');

  final List<String> cyclePath;
}

/// Thrown when a blueprint field exceeds the content boundary limits,
/// preventing the LLM from smuggling body prose into planning metadata.
class BlueprintContentBoundaryException extends BlueprintValidationException {
  const BlueprintContentBoundaryException(super.message, {super.field});
}

/// Thrown when the total planned character budget exceeds the resource limit.
class BlueprintBudgetExceededException extends BlueprintValidationException {
  const BlueprintBudgetExceededException(
    super.message, {
    required this.plannedLength,
    required this.budgetLimit,
  }) : super(field: 'targetCapacity');

  final int plannedLength;
  final int budgetLimit;
}

/// Strict validator for [ResourceBlueprint].
///
/// Ensures identity security, valid DAG dependencies, structural completeness,
/// content boundary constraints, and capacity adherence.
abstract final class BlueprintValidator {
  static const int maxNameLength = 100;
  static const int maxSummaryLength = 1000;
  static const int maxSectionTitleLength = 100;
  static const int maxSectionSummaryLength = 500;
  static const int maxPartTitleLength = 100;
  static const int maxPartGoalLength = 500;
  static const int minPartEstimatedLength = 10;

  /// Validates a [ResourceBlueprint] against all requirements.
  ///
  /// If [idPool] is provided, validates that all Section and Part IDs strictly
  /// belong to the authorized pre-allocated ID pool.
  static void validate(
    ResourceBlueprint blueprint, {
    BlueprintIdPool? idPool,
    int? maxBudgetOverride,
  }) {
    _validateStructureAndContentBoundaries(blueprint);
    _validateIds(blueprint, idPool: idPool);
    _validateDag(blueprint);
    _validateCapacity(blueprint, maxBudgetOverride: maxBudgetOverride);
  }

  static void _validateStructureAndContentBoundaries(
      ResourceBlueprint blueprint) {
    if (blueprint.suggestedName.trim().isEmpty) {
      throw const BlueprintValidationException(
        '规划资源名称不能为空',
        field: 'suggestedName',
      );
    }
    if (blueprint.suggestedName.trim().length > maxNameLength) {
      throw const BlueprintContentBoundaryException(
        '资源建议名称过长（超过 $maxNameLength 字符），不得在名称中混入正文',
        field: 'suggestedName',
      );
    }

    if (blueprint.summary.length > maxSummaryLength) {
      throw const BlueprintContentBoundaryException(
        '规划摘要过长（超过 $maxSummaryLength 字符），不得将摘要作为正文容器',
        field: 'summary',
      );
    }

    if (blueprint.sections.isEmpty) {
      throw const BlueprintValidationException(
        'Blueprint 必须至少包含一个 Section',
        field: 'sections',
      );
    }

    if (blueprint.allParts.isEmpty) {
      throw const BlueprintValidationException(
        'Blueprint 必须至少包含一个 Part',
        field: 'parts',
      );
    }

    for (final section in blueprint.sections) {
      if (section.id.trim().isEmpty) {
        throw const BlueprintIdException(
          'Section ID 不能为空',
          field: 'sections.id',
        );
      }
      if (section.title.trim().isEmpty) {
        throw BlueprintValidationException(
          'Section [${section.id}] 标题不能为空',
          field: 'sections.title',
        );
      }
      if (section.title.trim().length > maxSectionTitleLength) {
        throw BlueprintContentBoundaryException(
          'Section [${section.id}] 标题超过 $maxSectionTitleLength 字符限制',
          field: 'sections.title',
        );
      }
      if (section.summary.length > maxSectionSummaryLength) {
        throw BlueprintContentBoundaryException(
          'Section [${section.id}] 概述超过 $maxSectionSummaryLength 字符限制',
          field: 'sections.summary',
        );
      }
      if (section.sortOrder < 0) {
        throw BlueprintValidationException(
          'Section [${section.id}] 顺序编号不能为负数',
          field: 'sections.sortOrder',
        );
      }
      if (section.parts.isEmpty) {
        throw BlueprintValidationException(
          'Section [${section.id}] 必须至少包含一个 Part',
          field: 'sections.parts',
        );
      }

      for (final part in section.parts) {
        if (part.id.trim().isEmpty) {
          throw const BlueprintIdException(
            'Part ID 不能为空',
            field: 'parts.id',
          );
        }
        if (part.sectionId != section.id) {
          throw BlueprintIdException(
            'Part [${part.id}] 的 sectionId [${part.sectionId}] 与所属 Section [${section.id}] 不一致',
            field: 'parts.sectionId',
          );
        }
        if (part.title.trim().isEmpty) {
          throw BlueprintValidationException(
            'Part [${part.id}] 标题不能为空',
            field: 'parts.title',
          );
        }
        if (part.title.trim().length > maxPartTitleLength) {
          throw BlueprintContentBoundaryException(
            'Part [${part.id}] 标题超过 $maxPartTitleLength 字符限制',
            field: 'parts.title',
          );
        }
        if (part.generationGoal.trim().isEmpty) {
          throw BlueprintValidationException(
            'Part [${part.id}] 生成目标不能为空',
            field: 'parts.generationGoal',
          );
        }
        if (part.generationGoal.length > maxPartGoalLength) {
          throw BlueprintContentBoundaryException(
            'Part [${part.id}] 生成目标超过 $maxPartGoalLength 字符限制，禁止在生成目标中填入正文',
            field: 'parts.generationGoal',
          );
        }
        if (part.estimatedLength < minPartEstimatedLength) {
          throw BlueprintValidationException(
            'Part [${part.id}] 预计长度必须大于等于 $minPartEstimatedLength 字符',
            field: 'parts.estimatedLength',
          );
        }
        if (part.sortOrder < 0) {
          throw BlueprintValidationException(
            'Part [${part.id}] 顺序编号不能为负数',
            field: 'parts.sortOrder',
          );
        }
      }
    }
  }

  static void _validateIds(
    ResourceBlueprint blueprint, {
    BlueprintIdPool? idPool,
  }) {
    final seenSectionIds = <String>{};
    final seenPartIds = <String>{};

    for (final section in blueprint.sections) {
      if (!seenSectionIds.add(section.id)) {
        throw BlueprintIdException(
          '发现重复的 Section ID: [${section.id}]',
          field: 'sections.id',
        );
      }
      if (idPool != null && !idPool.isSectionAllowed(section.id)) {
        throw BlueprintIdException(
          'Section ID [${section.id}] 未在预分配 ID 许可池中',
          field: 'sections.id',
        );
      }

      for (final part in section.parts) {
        if (!seenPartIds.add(part.id)) {
          throw BlueprintIdException(
            '发现重复的 Part ID: [${part.id}]',
            field: 'parts.id',
          );
        }
        if (idPool != null && !idPool.isPartAllowed(part.id)) {
          throw BlueprintIdException(
            'Part ID [${part.id}] 未在预分配 ID 许可池中',
            field: 'parts.id',
          );
        }
      }
    }

    // Verify all dependency references exist
    for (final part in blueprint.allParts) {
      for (final depId in part.dependencies) {
        if (!seenPartIds.contains(depId)) {
          throw BlueprintIdException(
            'Part [${part.id}] 依赖了不存在的 Part ID: [$depId]',
            field: 'parts.dependencies',
          );
        }
      }
    }
  }

  static void _validateDag(ResourceBlueprint blueprint) {
    final allParts = blueprint.allParts;
    final partMap = {for (final p in allParts) p.id: p};

    // 1. Immediate self-dependency check
    for (final part in allParts) {
      if (part.dependencies.contains(part.id)) {
        throw BlueprintDagCycleException(
          'Part [${part.id}] 存在自环依赖 (${part.id} → ${part.id})',
          cyclePath: [part.id, part.id],
        );
      }
    }

    // 2. Cycle detection via 3-color DFS (0 = unvisited, 1 = visiting, 2 = visited)
    final state = <String, int>{for (final p in allParts) p.id: 0};
    final path = <String>[];

    void dfs(String currentId) {
      state[currentId] = 1; // visiting
      path.add(currentId);

      final part = partMap[currentId]!;
      for (final depId in part.dependencies) {
        final depState = state[depId] ?? 0;
        if (depState == 1) {
          // Cycle found!
          final cycleStartIndex = path.indexOf(depId);
          final cyclePath = path.sublist(cycleStartIndex)..add(depId);
          throw BlueprintDagCycleException(
            '依赖关系中存在循环依赖: ${cyclePath.join(' → ')}',
            cyclePath: cyclePath,
          );
        } else if (depState == 0) {
          dfs(depId);
        }
      }

      path.removeLast();
      state[currentId] = 2; // visited
    }

    for (final part in allParts) {
      if (state[part.id] == 0) {
        dfs(part.id);
      }
    }
  }

  static void _validateCapacity(
    ResourceBlueprint blueprint, {
    int? maxBudgetOverride,
  }) {
    final budgetLimit = maxBudgetOverride ??
        ResourceLimits.policyFor(blueprint.resourceType).nominalCharacters;
    final totalPlanned = blueprint.totalEstimatedLength;

    if (totalPlanned > budgetLimit) {
      throw BlueprintBudgetExceededException(
        'Blueprint 规划总字数预算 ($totalPlanned 字) 超过本次生成目标预算 ($budgetLimit 字)',
        plannedLength: totalPlanned,
        budgetLimit: budgetLimit,
      );
    }
  }
}
