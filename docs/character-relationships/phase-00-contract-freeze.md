# Related Character Generation — Phase 0 Contract Freeze

**Status: accepted for Phase 1.** This document records the implementation baseline and freezes the seven contracts required before any migration, repository, UI, Resource Studio, or prompt change. It is an audit/design artifact; Phase 0 makes no production-code or schema change.

## 1. Baseline

- Branch: `main`.
- Baseline before this Phase 0 commit: `78510ab` (`docs: design related character generation pipeline`).
- `origin/main` at audit start: `6c86f700d8b81d31d4043fbed5279a12e2c55f0d`; the design commit is local and the environment does not provide permission to push it. This Phase 0 commit must be pushed by the authorized maintainer before Phase 1.
- Current database schema: `DatabaseService.schemaVersion = 46`.
- Working tree contains pre-existing uncommitted UI, localization, generated localization, platform registration, dependency, and widget-test changes. They were preserved and are not part of this phase.
- No production Dart, test Dart, `database_service.dart`, ARB, or migration file is changed by Phase 0.

## 2. Character Identity Authority

### Frozen contract

`CharacterRelationshipEndpointId` is a unified content-tree `ResourceId`, represented as the immutable `resources.id` value for a `ResourceType.character` (or `ResourceType.npc` where the product explicitly permits NPC relationships). It is opaque and must never be a display name, mutable card name, creation-session ID, Adventure snapshot ID, or raw legacy card ID.

Evidence: `ResourceId` is the sealed resource-root identity in `lib/domain/resources/resource_contracts.dart`; tree repositories use it for generation, revisions, assembly, trash, and optimistic locking. `ResourceStudioCreationDraft`/blueprint confirmation and generation sessions also converge on `ResourceId`.

### Legacy strategy

Legacy `character_cards.id` is an input/source identifier only. Resolve it through the existing deterministic migration mapping `LegacyResourceMapper.resourceIdFor('character_cards', legacyId)`, which yields `res_legacy_character_cards_<legacyId>`, and require that the mapped tree resource exists and is a live character resource before creating a relationship. `ResourceReadFacade`/`ResourceAdventureView` remain read bridges; they do not make raw legacy IDs relationship identities.

A legacy-only card with no mapped tree resource is not silently assigned a synthetic relationship identity. Phase 1 must provide an explicit resolve/backfill path (or disable the relationship action with a clear reason) and test the failure. This is lazy compatibility through the existing canonical mapping, not name matching or an untracked ID alias.

`AdventureSelectedCharacter.characterId` remains an Adventure selection/snapshot reference. It is converted to/from the resource ID at the Adventure projection boundary and is never stored in the resource relationship table.

## 3. Relationship Domain Contract

The resource entity is `CharacterRelationship` with one row and two endpoint roles:

```text
id
endpointAResourceId
endpointBResourceId
relationType
endpointARole
endpointBRole
description
createdAt
updatedAt
```

`endpointAResourceId` and `endpointBResourceId` are canonical identity endpoints; `endpointARole` and `endpointBRole` carry semantics. A custom relationship uses both roles plus bounded description. A generated prose field is descriptive only; user configuration is authoritative.

The entity is separate from `AdventureCharacterRelationship`, which remains an Adventure snapshot/config model.

## 4. Direction Model

The frozen model is **one relationship entity plus endpoint perspectives**.

- Symmetric types (`friend`, `lover`, `rival`, `enemy`, `sibling`) may use the same role on both endpoints. The UI renders each endpoint’s own perspective.
- Directional types (`mentor/student`, `parent/child`, `employer/employee`, `guardian/ward`) require independently valid endpoint roles. Canonical endpoint ordering must not rewrite their meaning.
- Custom types require both endpoint roles; one `customRelationName` is insufficient to infer the reverse meaning.
- Prompt and UI projections choose the endpoint perspective by matching the viewing resource ID against endpoint A or B.

## 5. Relationship Identity

Canonicalize the two resource IDs using a stable, bytewise lexical ordering:

```text
canonicalA = min(endpoint ids)
canonicalB = max(endpoint ids)
```

The relationship identity is derived from `(canonicalA, canonicalB)` (or an opaque generated `id` guarded by the same unique pair). Canonical ordering is used only for identity and duplicate prevention; endpoint roles preserve semantic direction.

Constraints:

- `PRIMARY KEY (id)`.
- `UNIQUE (endpoint_a_resource_id, endpoint_b_resource_id)` because columns are always canonicalized.
- `CHECK (endpoint_a_resource_id <> endpoint_b_resource_id)`; self relationships are forbidden.
- Index each endpoint column for either-side detail queries.
- Create and update are separate application operations. A duplicate create returns a typed conflict; only an explicit edit may update the existing row. No silent upsert.

## 6. Persistence Authority

`CharacterRelationshipRepository` owns resource relationship CRUD and endpoint/lifecycle validation. A new application use case owns the accepted-character aggregate operation. UI and Resource Studio presentation controllers do not write SQLite.

The existing `IResourceTreeRepository` is the sole tree writer and already offers transaction-scoped methods through `DatabaseExecutor` for multi-statement tree/revision operations. Phase 1 must add the relationship repository’s equivalent in-transaction methods and a transaction coordinator; it must not create a second database authority.

## 7. Lifecycle

```text
draft (Creation Session only)
  → candidate (reviewable, no permanent edge)
  → accepted character candidate
  → character/resource persisted
  → relationship persisted
```

A permanent `CharacterRelationship` does not exist during streaming, candidate-only review, retry, cancellation, invalid JSON, validation failure, leaving Studio, or discard. Regeneration retains the draft but invalidates the previous candidate; only the accepted final candidate may be attached to the save transaction.

## 8. Trash, Restore, and Permanent Delete

### Trash

When either endpoint resource is soft-deleted through the existing resource trash/revision authority, normal relationship queries hide the edge because an endpoint is not live. The relationship row is retained and not independently soft-deleted, allowing restoration without reconstructing user data. Detail UI must not show an unknown ID.

### Restore

Restoring an endpoint through `ResourceTrashService`/revision restore makes its retained edges visible again only when the other endpoint is also live. Restore is idempotent and does not create duplicate edges.

### Permanent delete

Permanent purge of a resource must delete all relationship rows referencing that resource in the same purge transaction, before the resource identity is gone. The relationship repository is registered with the existing owned-state purge/lifecycle boundary. If the other endpoint is trashed, its retained unrelated edges remain intact; only edges touching the permanently purged endpoint are removed. This is cascade cleanup at the lifecycle service, not an unreviewed SQLite FK cascade, because current resource/trash ownership spans unified and legacy tables.

## 9. Generation Context Contract

The canonical application input is typed and one-to-one:

```text
CharacterGenerationReference {
  ResourceId resourceId
  String name
  String gender
  String profession
  String personality
  String background
  String appearance
  CharacterRelationshipSpecification relationship
}

CharacterRelationshipSpecification {
  String relationType
  String referenceCharacterRole
  String generatedCharacterRole
  String description
}
```

The exact Dart value types may follow existing project style, but these meanings are frozen. `CharacterReferenceContextMapper` resolves the canonical resource ID and bounded facts; the UI constructs a typed specification; the context builder preserves it; only the LLM adapter may project it to the current `relation`/`relationship` map shape. `relation` is a compatibility key only; the typed specification is the canonical field.

Relationship specification is **non-droppable** under token pressure. Per reference, retain P0 identity and relationship, then P1 personality and relationship-relevant background, P2 profession and bounded appearance, then optional facts. Never serialize full character JSON × N without the existing budget planner.

## 10. Worldview Scope

`ResourceProvenance.originWorldviewId` / the current character matching-worldview value is the source fact used by the existing `WorldviewCharacterScopePolicy`.

- A has no worldview: B has no forced inherited worldview.
- A has a worldview: B defaults to that same ID and the UI labels it as inherited.
- Every selected reference must pass the existing policy’s compatibility check. The application builder is the single validation authority; the UI may present the same result but may not invent another rule.
- Multiple references from different worlds are allowed only when the policy classifies the combination as compatible. Otherwise generation is blocked with a typed scope error; there is no silent merge or “first worldview wins”.
- An explicit user-selected B worldview is validated by the same policy and cannot be used to bypass it.

## 11. Adventure Boundary

```text
Resource CharacterRelationship (library authority)
        ↓ explicit selection-time projection
AdventureCharacterRelationship (snapshot/runtime authority)
```

Adventure may reuse stable relation vocabulary and a conversion utility, but it does not own, update, or backfill resource edges. Adventure edits affect only its snapshot; later resource edits affect future projections only. `AdventureCharacterRelationship.stableId` and its unordered IDs are not used for resource identity.

## 12. Atomic Transaction Boundary

The current `ResourceAiCreationOrchestrator.createAndStart` confirms a blueprint and allocates a `ResourceId` before generation; it is a planning/start boundary, not the accepted-character save boundary. The accepted boundary must be a new application use case invoked by Resource Studio’s final review/accept action:

```text
SaveGeneratedCharacterWithRelationships(
  AcceptedCharacterCandidate candidate,
  List<CharacterRelationshipDraft> drafts,
)
```

Its repository transaction is:

```text
BEGIN (DatabaseService database transaction)
  persist accepted B tree/resource and lifecycle metadata
  resolve B ResourceId
  validate each A is live and each draft is valid
  insert canonical A-B relationship rows
COMMIT
```

Any failure rolls back B and all edges. The UI must never perform sequential character/relationship writes. Because current high-level repositories open their own transactions while lower-level resource interfaces accept `DatabaseExecutor`, Phase 1 must add a composition boundary that passes one executor to both tree and relationship repository operations; a second independent `DatabaseService` is forbidden.

## 13. Schema Decision

**MIGRATION REQUIRED: YES.** There is no current resource-level relationship persistence. Adventure JSON is not a substitute and current legacy tables have no relationship authority.

Conceptual table (no table or version change in Phase 0):

```sql
resource_character_relationships (
  id TEXT PRIMARY KEY,
  endpoint_a_resource_id TEXT NOT NULL,
  endpoint_b_resource_id TEXT NOT NULL,
  relation_type TEXT NOT NULL,
  endpoint_a_role TEXT NOT NULL,
  endpoint_b_role TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(endpoint_a_resource_id, endpoint_b_resource_id),
  CHECK(endpoint_a_resource_id <> endpoint_b_resource_id)
)
```

Add endpoint A/B indexes. FK enforcement and exact target table are decided in Phase 1 against the then-current unified resource schema; lifecycle purge remains an application-owned cleanup even if FKs are later added. No `DatabaseService.schemaVersion` is changed here. The next version is selected when Phase 1 begins from the current schema, not from this document.

## 14. Phase 1 Exact Scope

Phase 1 may change only:

- new resource relationship domain/value objects and validation;
- relationship repository interface/implementation and provider wiring;
- migration creating the table/indexes at the then-current schema version;
- legacy-to-`ResourceId` resolution using existing `LegacyResourceMapper`/read authority, including explicit handling for legacy-only rows;
- lifecycle purge/restore hooks required to satisfy this contract;
- focused unit/repository tests for identity, direction, duplicates, self edges, endpoint lifecycle, and migration idempotence;
- this document or a Phase 1 implementation report when a current-schema fact changes.

Phase 1 must not modify Resource Studio, UI, ARB, prompt composition, Adventure projection, or unrelated code.

## 15. Non-goals

- No generation context implementation or map removal.
- No new character-detail entry point or relation editor.
- No Resource Studio changes.
- No prompt changes.
- No Adventure model replacement.
- No migration of existing Adventure relationships into resources.
- No schema version guesswork outside the implementation-time migration.
- No cleanup of pre-existing worktree changes.

## Phase 0 Acceptance Checklist

- [x] Canonical character resource ID is `ResourceId`.
- [x] Legacy ID mapping and legacy-only behavior are explicit.
- [x] Relationship entity and endpoint roles are frozen.
- [x] Canonical pair identity, duplicate policy, and self-edge policy are frozen.
- [x] Trash, restore, and permanent purge semantics are frozen.
- [x] Typed generation contract and non-droppable relationship rule are frozen.
- [x] Worldview inheritance and multi-world conflict behavior are frozen.
- [x] Atomic save boundary is identified as a new application use case composed over one `DatabaseExecutor` transaction.
- [x] Resource and Adventure authorities are separated.
- [x] Migration decision is `YES`; no schema version is changed in Phase 0.
- [x] Phase 1 scope and non-goals contain no architecture TBD.
