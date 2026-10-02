/// Deterministic, cross-process stable hashing for voice assignment.
///
/// Dart's built-in `hashCode` is not stable across processes or platforms, so it
/// must never be used to derive a persisted voice assignment. This implements
/// the classic 32-bit FNV-1a hash, which is stable everywhere (including the
/// web, where 64-bit integer arithmetic is not available).
library;

/// Returns a stable unsigned 32-bit FNV-1a hash of [input].
int stableHash32(String input) {
  const int offsetBasis = 0x811c9dc5;
  const int prime = 0x01000193;
  var hash = offsetBasis;
  for (final unit in input.codeUnits) {
    hash ^= unit & 0xff;
    hash = (hash * prime) & 0xffffffff;
    // Fold the high byte of multi-byte code units separately so that, e.g.,
    // CJK resource names still produce well-distributed hashes.
    if (unit > 0xff) {
      hash ^= (unit >> 8) & 0xff;
      hash = (hash * prime) & 0xffffffff;
    }
  }
  return hash;
}
