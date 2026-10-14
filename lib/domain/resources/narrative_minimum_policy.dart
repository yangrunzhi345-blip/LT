import 'resource_limits.dart';

/// U6 dynamic content contract (approved v0.1): the client-authoritative
/// minimum effective body length for a `narrative` Part.
///
/// The minimum is a graduated accumulation of the Part's final planned length
/// `p` rather than a flat ratio, so a long Part is never forced to the same
/// proportion as a short one, while every Part still carries a deterministic
/// lower bound the validator and the commit can share:
///
/// ```text
///   m = ceil( 0.50*min(p,200)
///           + 0.40*min(max(p-200,0),600)
///           + 0.30*max(p-800,0) )
/// ```
///
/// Meaning of the three segments (UTF-16 units): the first 200 characters count
/// at 50%, the increment from 200 to 800 at 40%, and everything above 800 at
/// 30%. The approved planned-length domain is `80 <= p <= K`; there is no
/// separate absolute character floor, and `p < 80` must be re-planned, merged or
/// reclassified instead of silently receiving a contract.
///
/// The arithmetic is pure integer: with `a/b/c` the three segment lengths,
/// `0.50a + 0.40b + 0.30c = (50a + 40b + 30c) / 100`, so the ceiling is exactly
/// `(50a + 40b + 30c + 99) ~/ 100`. No floating-point rounding can move the
/// boundary that a confirmed contract enforces.
///
/// This is a pure policy value: it never generates a contract, never reads the
/// database and never talks to the model. It is the single authority the
/// Planner, Normalizer, Validator and Repository must share once U6-B wires it
/// into the blueprint pipeline; U6-A only publishes the function and its tests.
abstract final class NarrativeMinimumPolicy {
  /// End of the first accumulation segment (UTF-16 units).
  static const int firstBreakpoint = 200;

  /// End of the second accumulation segment (UTF-16 units).
  static const int secondBreakpoint = 800;

  /// Percent charged on the first `[0, 200]` segment.
  static const int firstSegmentPercent = 50;

  /// Percent charged on the `(200, 800]` increment.
  static const int secondSegmentPercent = 40;

  /// Percent charged on the `(800, K]` increment.
  static const int thirdSegmentPercent = 30;

  /// The approved lowest planned length for a strict narrative contract.
  ///
  /// Below this the planner must increase the plan, merge the Part, or
  /// reclassify it (U6 §2.2 / product decision 3); no strict contract is
  /// created and no Part is allowed to silently run without a contract.
  static const int minimumPlannedLength = 80;

  /// Highest planned length accepted here: the existing single-Part cap `K`.
  ///
  /// The absolute capacity `A`, elasticity `E` and transport cap `K` are
  /// unchanged by U6; this bound only mirrors `K`.
  static const int maximumPlannedLength = ResourceLimits.maxPartCharacters;

  /// Whether a planned length can carry a strict narrative contract.
  ///
  /// Equivalent to the `minimumCharactersFor` domain check, exposed so a future
  /// planner/review step can ask the question without catching an exception.
  static bool isPlannable(int plannedLength) =>
      plannedLength >= minimumPlannedLength &&
      plannedLength <= maximumPlannedLength;

  /// The minimum effective narrative body length for a final planned length
  /// [plannedLength].
  ///
  /// Effective length is the `trim()`-ed UTF-16 count used by
  /// `PartContentRequirementsValidator`; resource capacity still counts the
  /// untrimmed `String.length`, so this never changes the capacity formula.
  ///
  /// Fail-closed: a planned length outside
  /// `[minimumPlannedLength, maximumPlannedLength]` throws [ArgumentError]
  /// instead of returning a guessed value, because such a Part must be
  /// re-planned or reclassified rather than silently contracted.
  static int minimumCharactersFor(int plannedLength) {
    if (!isPlannable(plannedLength)) {
      throw ArgumentError.value(
        plannedLength,
        'plannedLength',
        'must be between $minimumPlannedLength and $maximumPlannedLength',
      );
    }
    // Segment lengths; each is clamped to its own window with integer math.
    final first =
        plannedLength < firstBreakpoint ? plannedLength : firstBreakpoint;
    final firstIncrement = plannedLength - firstBreakpoint;
    final second = firstIncrement <= 0
        ? 0
        : (firstIncrement < (secondBreakpoint - firstBreakpoint)
            ? firstIncrement
            : (secondBreakpoint - firstBreakpoint));
    final secondIncrement = plannedLength - secondBreakpoint;
    final third = secondIncrement <= 0 ? 0 : secondIncrement;

    final weighted = firstSegmentPercent * first +
        secondSegmentPercent * second +
        thirdSegmentPercent * third;
    // ceil(weighted / 100) for a non-negative integer numerator.
    return (weighted + 99) ~/ 100;
  }
}
