# README Structure Plan

## Audience and purpose

The root README is the GitHub entry point for international users, contributors, and people evaluating the project. It should explain the product and the shortest path to a local development run without duplicating internal design documents.

## Planned section order

1. **Title and language navigation** — project name, badges, and links to all five README languages.
2. **Introduction** — one paragraph positioning LT as a local-first AI interactive storytelling platform.
3. **Key features** — only capabilities present in the current source tree.
4. **Architecture overview** — concise flow from Flutter UI through application/domain boundaries to repositories, SQLite, model gateways, and platform services; describe the transitional structure accurately.
5. **AI generation system** — OpenAI-compatible configuration, resource creation/import, blueprints, streaming, validation, and Adventure turn handling.
6. **Character and World system** — worldview, character, NPC, structured sections/parts, snapshots, revisions, and assembly readiness.
7. **Resource library** — search, editing, autosave, history, trash, compression, and Resource Studio.
8. **Reading experience** — Adventure sessions, branches, state-aware turns, translation, reasoning display, and read-aloud/TTS.
9. **Multi-language support** — five supported UI locales and the language files.
10. **Screenshots** — an honest placeholder because no UI screenshots are tracked; include the tracked logo as the available visual asset.
11. **Installation** — prerequisites, clone, dependency setup, API/model configuration, and target-specific run examples.
12. **Development** — format, analyze, test, benchmark, and useful source links.
13. **Roadmap** — improvements that are clearly future-facing, without presenting them as shipped features.
14. **Contributing** — focused changes, documentation, tests, and issue/PR expectations.
15. **License** — state that no root license file is currently included and explain how to ask about reuse.

## Content rules

- Use English in the primary README; translations follow the same section order and capability boundaries.
- Prefer stable behavior and source paths over release snapshots or internal phase numbers.
- Do not claim web as a supported product target, generic agent runtime, graph/vector storage, or autonomous cross-resource decision making.
- Use relative links that resolve from the repository root.
- Keep the page scannable: short paragraphs, feature bullets, and a small architecture diagram.
