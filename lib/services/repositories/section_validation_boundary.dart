import 'package:sqflite/sqflite.dart';

import '../../domain/resources/resource_contracts.dart';
import '../../domain/resources/section_control.dart';
import '../../domain/resources/section_control_repository.dart';

/// Transaction-scoped view of the section verdict columns.
///
/// Declared in the service layer (not the contract layer) for the same reason
/// [ISectionControlRepository] keeps its SQL out of the domain: it exposes
/// `DatabaseExecutor`, which the pure-Dart contract layer must not depend on.
///
/// Phase 9 needs it because the single Part-content commit path writes the body,
/// downgrades the section verdict and flips the revision head in **one**
/// transaction. Reading the verdict through a separate connection would allow a
/// section to keep a `valid` verdict that describes content that no longer
/// exists.
abstract interface class ISectionValidationBoundary {
  /// Reads one section control row inside [db], or null when it is gone.
  Future<SectionControlRow?> findSectionControlRowInTransaction(
    DatabaseExecutor db,
    SectionId id,
  );

  /// Writes one verdict inside [db] under optimistic locking.
  Future<void> updateSectionValidationInTransaction(
    DatabaseExecutor db, {
    required SectionId id,
    required String expectedUpdatedAt,
    required SectionValidationState state,
    required String message,
    DateTime? validatedAt,
  });
}
