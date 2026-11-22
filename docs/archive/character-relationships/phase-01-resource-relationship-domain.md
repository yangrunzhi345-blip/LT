# Phase 1 — Resource Character Relationship Domain

## Baseline

- Starting `HEAD`: `ee6fc97216cb901d4edc76ceffd407fe17a2f178`
- Starting `origin/main`: `ee6fc97216cb901d4edc76ceffd407fe17a2f178`
- Starting schema: 46
- The pre-existing UI, localization, generated localization, platform,
  dependency, and widget-test worktree changes were preserved.

## Schema

- Schema advanced from 46 to 47.
- Fresh databases create `resource_character_relationships` directly.
- Existing databases run an idempotent v46 → v47 migration.
- No existing rows are copied or converted into relationships.

## Domain

`CharacterRelationship` stores the canonical endpoint pair, each endpoint's
role, a stable machine relation type, bounded description, and timestamps.
`CharacterRelationshipEndpoints.canonicalize` is the only endpoint ordering
helper. It sorts by opaque `ResourceId` and moves the paired role with its
endpoint, preserving directional meaning.

Supported machine types include symmetric friend/family/enemy/companion/
lover/rival/sibling/stranger values, directional mentor-student,
parent-child, employer-employee and guardian-ward values, and custom.
Directional types require the matching role pair; custom always stores both
perspectives. Empty endpoints, self edges, empty roles, invalid types and
overlong descriptions fail with typed domain errors.

## Persistence

`CharacterRelationshipRepository` owns CRUD and exposes `createInTransaction`
and `deleteForResourcePurge` for composition with an existing
`DatabaseExecutor`. It validates that both endpoints exist as live
`character`/`npc` resources before insert. Duplicate pairs return a typed
conflict; there is no upsert. `listForResource` joins both resource rows and
only returns edges whose endpoints are both live.

The table has:

- `id` primary key;
- unique canonical `(endpoint_a_resource_id, endpoint_b_resource_id)`;
- self-edge `CHECK` constraint;
- indexes for endpoint A and endpoint B;
- no foreign keys, because resource trash/purge ownership is application
  controlled across unified and legacy data.

## Legacy resolution

`LegacyResourceMapper.resolveLiveCharacterResourceId` uses the existing
deterministic `res_legacy_<source-table>_<legacy-id>` mapping, then verifies
the mapped unified resource exists, has the expected character/NPC type, and
is live. Missing, wrong-type, trashed, empty, or non-card inputs throw
`LegacyResourceUnresolvedException`; a raw legacy ID is never written as an
endpoint.

## Lifecycle

- Trash retains relationship rows; repository queries hide edges while either
  endpoint is trashed.
- Restore needs no relationship mutation; once both resources are live, the
  same row is visible again.
- `ResourceOwnedStatePurger` deletes all touching edges inside the existing
  permanent-purge transaction. Unrelated edges remain intact.

## Tests and verification

`test/services/character_relationship_repository_test.dart` covers canonical
role movement, domain/repository validation, create/read/update, typed
duplicate conflict, trash visibility, purge isolation, fresh schema
constraints, v46 → v47 upgrade preservation, and legacy resolution failure.

The following commands passed:

```text
flutter test test/services/character_relationship_repository_test.dart
flutter analyze
git diff --check
```

## Deferred

Generation context typing, Resource Studio and character-detail UI, prompts,
Adventure projection, and aggregate save orchestration remain deferred to the
later phases specified by the frozen contract.
