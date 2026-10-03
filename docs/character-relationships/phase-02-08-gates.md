# Related Character Generation Phase Gates

This record is the formal Phase 2–8 handoff used by the Phase 9 integrated
acceptance. It reflects the current code and committed implementation history;
Phase 0 and Phase 1 records remain authoritative for their earlier contracts.

| Phase | Status | Gate evidence | Implementation commits |
| --- | --- | --- | --- |
| 2 — typed generation reference | ACCEPTED | Typed `ResourceId` references, per-reference facts, serialization, mixed-world and cross-world scope failures, and prompt constraint propagation are covered by the generation/reference suites. | `73d828e`, `ef38ad6`, `225831b` |
| 3 — Resource Studio integration | ACCEPTED | Creation-session draft persistence, retry/resume propagation, stable candidate identity, blueprint/session revalidation, and Resource Studio as the single generation authority are covered by pipeline and runtime tests. | `d8c6c80`, `c28b4e3`, `4dc247c` |
| 4 — creation and detail UX | ACCEPTED | Locked source entry, zero/one/many typed references, relationship editing, localized labels, SVG actions, and responsive widget coverage are present. | `9892ff2`, `c7b714c` |
| 5 — atomic persistence | ACCEPTED | Real SQLite transaction tests cover commit, rollback, duplicate submit, endpoint validation, candidate metadata, and stale blueprint revision rejection. | `d56215d`, `a05eeb8`, `61ad90e` |
| 6 — relationship management | ACCEPTED | Application-boundary list/update/delete, perspective projection, trash/restore visibility, and purge cleanup are covered by relationship management tests. | `bf69881`, `c7b714c` |
| 7 — Adventure projection | ACCEPTED | Creation-time projection requires both selected endpoints, stores a deep-copied snapshot, and later Resource edits do not mutate existing Adventures. | `edb6d27`, `ef38ad6` |
| 8 — i18n and responsive convergence | ACCEPTED | Six locale ARB files and generated localizations are updated; 320 px, text-scale, overflow, and menu-boundary checks pass. | `c7b714c` |

The production runtime acceptance seam is separately covered by
`test/application/resources/resource_studio_runtime_acceptance_test.dart`,
which uses the real SQLite repositories and the production runtime adapter.
Phase 9 records the complete matrix, build evidence, mutation probes, and
remaining-finding classification.
