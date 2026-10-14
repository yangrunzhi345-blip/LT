import 'content_requirements.dart';
import 'narrative_minimum_policy.dart';
import 'resource_blueprint.dart';

/// Client-trusted content spec for ONE Part (U6).
///
/// Only the client produces these: an authorized resource template, or an
/// explicit user decision in the blueprint review. The model may not supply a
/// [PartContentSpec]; a model-proposed type is at most a hint the client
/// discards (U6 §3). The model NEVER decides [minimumCharacters] — that is
/// derived here from the approved policy.
final class PartContentSpec {
  const PartContentSpec({
    this.kind = PartContentKind.narrative,
    this.required = true,
    this.requiredHeadings = const <String>[],
    this.requiredFields = const <String>[],
  });

  final PartContentKind kind;
  final bool required;
  final List<String> requiredHeadings;
  final List<String> requiredFields;
}

/// Why a Part could not receive a client-authoritative contract.
enum BlueprintContractGapReason {
  /// A narrative Part whose final planned length is below the approved minimum.
  plannedLengthBelowMinimum,

  /// A structured Part with no client-confirmed required fields.
  structuredFieldsUnconfirmed,
}

final class BlueprintContractGap {
  const BlueprintContractGap({
    required this.partId,
    required this.reason,
    required this.message,
  });

  final String partId;
  final BlueprintContractGapReason reason;
  final String message;
}

final class BlueprintContentContractResult {
  const BlueprintContentContractResult({
    required this.blueprint,
    required this.gaps,
  });

  /// The blueprint with every contracted Part carrying a client-authoritative
  /// [ContentRequirements]. Parts listed in [gaps] keep a null contract.
  final ResourceBlueprint blueprint;
  final List<BlueprintContractGap> gaps;

  bool get isComplete => gaps.isEmpty;
}

/// Generates the client-authoritative [ContentRequirements] for every Part of a
/// blueprint whose final planned length is already decided (i.e. after
/// `BlueprintBudgetNormalizer`).
///
/// This is the single place a new Part's minimum is decided (U6 §5): it reads
/// [NarrativeMinimumPolicy] for narrative Parts and never trusts a model-supplied
/// minimum/profile/fields. Any contract already present on a Part (e.g. one the
/// model tried to smuggle in) is replaced — it can only lower a requirement, so
/// it is never kept.
///
/// An untyped Part defaults to FREE NARRATIVE (U6 §2.3): the safe side, since a
/// part is never left without a contract, and a narrative minimum is stricter
/// than scalar/structured. Scalar/structured are used only when a trusted
/// [PartContentSpec] says so.
abstract final class BlueprintContentContractPlanner {
  /// The conservative default: an untyped Part is free narrative, required.
  static const PartContentSpec defaultSpec = PartContentSpec();

  /// Version stamped on every contract-enforced blueprint (U6 v0.1).
  static const int contentContractVersion = 1;

  static BlueprintContentContractResult apply(
    ResourceBlueprint blueprint, {
    Map<String, PartContentSpec> specs = const <String, PartContentSpec>{},
  }) {
    final gaps = <BlueprintContractGap>[];
    final sections = <BlueprintSection>[];
    for (final section in blueprint.sections) {
      final parts = <BlueprintPart>[];
      for (final part in section.parts) {
        final spec = specs[part.id] ?? defaultSpec;
        final contract = _contractFor(part, spec, gaps);
        // Rebuild the Part rather than copyWith: `copyWith(null)` keeps the old
        // value, and a model-supplied contract must be cleared when unresolved.
        parts.add(BlueprintPart(
          id: part.id,
          sectionId: part.sectionId,
          title: part.title,
          generationGoal: part.generationGoal,
          estimatedLength: part.estimatedLength,
          dependencies: part.dependencies,
          sortOrder: part.sortOrder,
          contentRequirements: contract,
        ));
      }
      sections.add(section.copyWith(parts: parts));
    }
    return BlueprintContentContractResult(
      blueprint: blueprint.copyWith(
        sections: sections,
        // Marks this plan as U6 contract-enforced: confirm must reject it unless
        // every Part ends up with a valid client contract (including the case
        // where a gap left every Part unresolved).
        contentContractVersion: contentContractVersion,
      ),
      gaps: gaps,
    );
  }

  static ContentRequirements? _contractFor(
    BlueprintPart part,
    PartContentSpec spec,
    List<BlueprintContractGap> gaps,
  ) {
    final planned = part.estimatedLength;
    switch (spec.kind) {
      case PartContentKind.narrative:
        if (planned < NarrativeMinimumPolicy.minimumPlannedLength) {
          gaps.add(BlueprintContractGap(
            partId: part.id,
            reason: BlueprintContractGapReason.plannedLengthBelowMinimum,
            message: 'Part [${part.id}] 计划长度 $planned 低于叙述最低可规划长度 '
                '${NarrativeMinimumPolicy.minimumPlannedLength}，请增加容量、合并该 Part 或改为 Scalar/Structured',
          ));
          return null;
        }
        return ContentRequirements(
          kind: PartContentKind.narrative,
          minimumCharacters:
              NarrativeMinimumPolicy.minimumCharactersFor(planned),
          validationProfile: PartValidationProfile.narrativeSectionsV1,
          required: spec.required,
          requiredHeadings: spec.requiredHeadings,
        );
      case PartContentKind.scalar:
        return ContentRequirements(
          kind: PartContentKind.scalar,
          minimumCharacters: 1,
          validationProfile: PartValidationProfile.scalarTextV1,
          required: spec.required,
        );
      case PartContentKind.structured:
        if (spec.requiredFields.isEmpty) {
          gaps.add(BlueprintContractGap(
            partId: part.id,
            reason: BlueprintContractGapReason.structuredFieldsUnconfirmed,
            message: 'Part [${part.id}] 采用 Structured 但缺少客户端确认的必填字段，'
                '不得使用模型自报字段',
          ));
          return null;
        }
        return ContentRequirements(
          kind: PartContentKind.structured,
          minimumCharacters: 1,
          validationProfile: PartValidationProfile.structuredObjectV1,
          required: spec.required,
          requiredFields: spec.requiredFields,
        );
    }
  }
}
