import '../../../../../controllers/resource_crud_controller.dart';
import '../../../../../domain/resources/resource_contracts.dart';
import '../../../../../models/resource_library_mode.dart';
import '../../domain/models/resource_library_view_state.dart';

abstract interface class ResourceLibraryRuntime {
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode);

  Future<ResourceOperationResult> moveToTrash({
    required ResourceLibraryItem item,
    required ResourceLibraryMode mode,
  });

  Future<String> createManual({
    required ResourceType type,
    required String name,
    required String summary,
    required ResourceLibraryMode mode,
  });
}
