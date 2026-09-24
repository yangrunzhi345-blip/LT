# README Rewrite Report

Date: 2026-09-24
Baseline: `main` at `8981942`

## 1. Modified and added files

- [README.md](README.md) — rewritten as the English primary entry point.
- [README.zh-CN.md](README.zh-CN.md) — added Simplified Chinese translation.
- [README.zh-TW.md](README.zh-TW.md) — added Traditional Chinese translation.
- [README.ja.md](README.ja.md) — added Japanese translation.
- [README.ko.md](README.ko.md) — added Korean translation.
- [readme-audit.md](docs/documentation/readme-audit.md) — source and documentation audit.
- [readme-structure-plan.md](docs/documentation/readme-structure-plan.md) — README structure and content plan.

No Dart, Flutter, database, business, test, dependency, or version files were changed.

## 2. Removed or corrected outdated descriptions

- Replaced the Chinese-only root entry point with an English GitHub entry point.
- Removed the stale `1.1.15+18` and dated test-count snapshot; the current package version is `1.1.16+19`.
- Removed long internal phase and legacy implementation detail from the product README.
- Removed language that could present generic agents, graph/vector storage, or autonomous cross-resource decisions as shipped features.
- Corrected the license statement: no root `LICENSE` file is currently tracked.
- Kept current product boundaries explicit, including the five supported product platforms and five UI locales.

## 3. Added content

- Unified language navigation on all five README files.
- Current feature summary covering Adventure, resource generation, Resource Studio, stateful storytelling, and read-aloud.
- Architecture overview that reflects the repository's transitional layered structure.
- AI generation, character/world, resource library, reading experience, localization, screenshots, installation, development, roadmap, contributing, and license sections.
- Honest screenshots note because no UI screenshots are currently committed.

## 4. Consistency with current code

The content was checked against `pubspec.yaml`, `lib/main.dart`, `lib/core/localization/app_locale.dart`, `lib/core/router/app_router.dart`, `lib/services/database_service.dart`, the `lib/features/` tree, platform project directories, and tracked documentation. The README describes SQLite schema 44 and the five `AppLocale` values in the audit document, while the public README keeps only stable user-facing facts.

## 5. Markdown checks

- Relative Markdown links and image paths: passed for all five README files (no missing targets).
- Heading hierarchy: passed for all five README files.
- `git diff --check`: passed.
- Spell checker: no `aspell`, `vale`, or `markdownlint` executable is installed in the environment; content received manual language and consistency review.
- No application or test commands were run because this task is documentation-only.

## Git state

The worktree is intentionally left uncommitted for human confirmation, as requested. Before commit, review:

```bash
git status --short
git diff --stat
git diff --check
```
