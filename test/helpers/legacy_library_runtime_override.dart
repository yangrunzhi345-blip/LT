import 'package:lt_dialogue/features/resource_library/application/use_cases/resource_library_runtime.dart';
import 'package:lt_dialogue/providers/riverpod_providers.dart';

/// Pins the library runtime to the legacy tree/Studio implementation.
///
/// Widget tests that assert the retired Studio creation flow must opt back into
/// it explicitly, because production now uses lightweight setting cards. Phase
/// 5c deletes both the Studio flow and these tests.
dynamic legacyLibraryRuntimeOverride() =>
    resourceLibraryRuntimeProvider.overrideWith(
      (ref) => ProductionResourceLibraryRuntime(
        crud: ref.read(resourceCrudControllerProvider),
        studio: ref.read(resourceStudioRuntimeProvider),
        reconciler: ref.read(resourceLifecycleReconcilerProvider),
      ),
    );
