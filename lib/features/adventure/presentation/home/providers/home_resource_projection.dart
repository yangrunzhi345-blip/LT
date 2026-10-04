import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../../../../providers/riverpod_providers.dart';
import '../../../../resource_library/domain/models/resource_library_view_state.dart';

/// Home summary of the user's resource library.
///
/// This is a *derived projection*, not a second source of truth: it holds no
/// persistence and performs no query of its own. Both fields are computed by
/// splitting the single `allResources` result of the existing
/// [resourceLibraryRuntimeProvider] — the exact authority the Resource Library
/// screen reads — by [ResourceType].
final class HomeResourceProjection {
  const HomeResourceProjection({
    required this.worldviews,
    required this.characters,
  });

  final List<ResourceLibraryItem> worldviews;
  final List<ResourceLibraryItem> characters;
}

/// Reactive projection consumed by the Adventure home.
///
/// It is `autoDispose` so that leaving the home (e.g. to the library, the
/// creator or a Studio editor) and coming back always re-reads the authority
/// instead of reusing a stale summary. The provider therefore distinguishes
/// [AsyncLoading], [AsyncData] (including an empty list) and [AsyncError]
/// rather than miscasting an in-flight load as an empty library.
final homeResourceProjectionProvider =
    FutureProvider<HomeResourceProjection>((ref) async {
  final runtime = ref.watch(resourceLibraryRuntimeProvider);
  final all = await runtime.load(ResourceLibraryMode.adventure);
  return HomeResourceProjection(
    worldviews: List<ResourceLibraryItem>.unmodifiable(
      all.where((item) => item.type == ResourceType.worldview),
    ),
    characters: List<ResourceLibraryItem>.unmodifiable(
      all.where((item) => item.type == ResourceType.character),
    ),
  );
}, isAutoDispose: true);
