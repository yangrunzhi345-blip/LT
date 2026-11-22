import '../../../../../models/resource_library_mode.dart';
import '../../domain/models/resource_library_view_state.dart';

abstract interface class ResourceLibraryRuntime {
  Future<List<ResourceLibraryItem>> load(ResourceLibraryMode mode);
}
