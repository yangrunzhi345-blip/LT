/// Lifecycle state surfaced by the resource library presentation layer.
///
/// Only the enum is kept here: the projection and reconciler that produced it
/// are part of the retiring creation/assembly pipeline. The lightweight card
/// library reads its state from the setting card store instead.
enum ResourceLifecycleState {
  missing,
  draft,
  planning,
  generating,
  validating,
  paused,
  recovering,
  ready,
  failed,
  archived,
}
