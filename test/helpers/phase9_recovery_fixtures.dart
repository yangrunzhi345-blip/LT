import 'package:lt_dialogue/application/resources/compression_job_repository.dart';
import 'package:lt_dialogue/application/resources/legacy_library_row_purger.dart';
import 'package:lt_dialogue/application/resources/part_content_commit_service.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_repository.dart';
import 'package:lt_dialogue/application/resources/resource_autosave_service.dart';
import 'package:lt_dialogue/application/resources/resource_compression_publisher.dart';
import 'package:lt_dialogue/application/resources/resource_generation_task_repository.dart';
import 'package:lt_dialogue/application/resources/resource_library_trash_bridge.dart';
import 'package:lt_dialogue/application/resources/resource_revision_repository.dart';
import 'package:lt_dialogue/application/resources/resource_revision_service.dart';
import 'package:lt_dialogue/application/resources/resource_trash_repository.dart';
import 'package:lt_dialogue/application/resources/resource_trash_service.dart';
import 'package:lt_dialogue/domain/resources/resource_revision.dart';
import 'package:lt_dialogue/services/repositories/resource_tree_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/section_control_repository_impl.dart';
import 'package:lt_dialogue/services/repositories/library_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Assembles the Phase 9 recovery stack the same way the production composition
/// roots do (`DatabaseService` and `riverpod_providers`).
///
/// Tests that touch delete / revision / autosave / bin behaviour must go through
/// this wiring rather than constructing one repository in isolation: the audit
/// found that a half-wired stack silently fell back to the destructive legacy
/// path, and the fixture exists so "the test used a different stack than
/// production" cannot happen again.
final class Phase9RecoveryFixture {
  Phase9RecoveryFixture({
    required this.getDb,
    this.retention,
  }) {
    tree = ResourceTreeRepositoryImpl(getDb: getDb);
    revisions = ResourceRevisionRepositoryImpl(getDb: getDb);
    captureEngine = RevisionCaptureEngine(
      revisionRepository: revisions,
      treeBoundary: tree,
    );
    tasks = PartGenerationTaskRepositoryImpl(
      getDb: getDb,
      revisionBoundary: captureEngine,
    );
    revisionService = ResourceRevisionService(
      revisionRepository: revisions,
      captureEngine: captureEngine,
      treeBoundary: tree,
      getDb: getDb,
      taskReset: tasks,
      retention: retention ?? RevisionRetentionPolicy.defaultRetention,
    );
    trashRepository = ResourceTrashRepositoryImpl(getDb: getDb);
    autosaveRepository = ResourceAutosaveRepositoryImpl(getDb: getDb);
    compressionJobs = CompressionJobRepositoryImpl(getDb: getDb);
    partCommit = PartContentCommitService(
      treeBoundary: tree,
      validationBoundary: SectionControlRepositoryImpl(getDb: getDb),
      captureEngine: captureEngine,
      autosaveRepository: autosaveRepository,
      getDb: getDb,
      taskReset: tasks,
    );
    legacyPurger = LegacyLibraryRowPurger(getDb: getDb);
    trash = ResourceTrashService(
      repository: trashRepository,
      treeBoundary: tree,
      captureEngine: captureEngine,
      getDb: getDb,
      legacyRowPort: legacyPurger,
    );
    libraryTrash =
        ResourceLibraryTrashBridge(getDb: getDb, trashService: trash);
    publisher = CompressionPublisher(
      jobRepository: compressionJobs,
      revisionService: revisionService,
      getDb: getDb,
    );
  }

  final Future<Database> Function() getDb;
  final Duration? retention;

  late final ResourceTreeRepositoryImpl tree;
  late final ResourceRevisionRepositoryImpl revisions;
  late final RevisionCaptureEngine captureEngine;
  late final PartGenerationTaskRepositoryImpl tasks;
  late final ResourceRevisionService revisionService;
  late final ResourceTrashRepositoryImpl trashRepository;
  late final ResourceAutosaveRepositoryImpl autosaveRepository;
  late final CompressionJobRepositoryImpl compressionJobs;
  late final PartContentCommitService partCommit;
  late final LegacyLibraryRowPurger legacyPurger;
  late final ResourceTrashService trash;
  late final ResourceLibraryTrashBridge libraryTrash;
  late final CompressionPublisher publisher;

  /// A library repository wired to the recycle bin, i.e. production shape.
  LibraryRepositoryImpl libraryRepository() =>
      LibraryRepositoryImpl(getDb: getDb, trashBridge: libraryTrash);

  /// A library repository **without** the bin bridge, for the fail-closed test.
  LibraryRepositoryImpl unwiredLibraryRepository() =>
      LibraryRepositoryImpl(getDb: getDb);

  /// One autosave session per editor, matching the production factory.
  ResourceAutosaveService newAutosave({
    Duration debounce = const Duration(milliseconds: 40),
    Duration maxBufferedAge = const Duration(seconds: 2),
    void Function(AutosaveFlushResult result)? onFlushed,
  }) =>
      ResourceAutosaveService(
        journal: autosaveRepository,
        committer: partCommit,
        treeBoundary: tree,
        getDb: getDb,
        debounce: debounce,
        maxBufferedAge: maxBufferedAge,
        onFlushed: onFlushed,
      );
}
