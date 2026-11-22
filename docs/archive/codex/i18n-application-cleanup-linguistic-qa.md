# i18n Application Cleanup & Linguistic QA

## Baseline

- Start `HEAD`: `e957f937386d5882a5bbde7797e8dcc7896bfd1d`
- `origin/main` at baseline: `e957f937386d5882a5bbde7797e8dcc7896bfd1d`
- The working tree was clean at the start of this task.
- Error/Event typed architecture from the previous round was retained.

## Application Layer Audit

Scanned `lib/domain`, `lib/application`, `lib/services`, `lib/managers`, and
`lib/engines` for `AppLocalizations`, `BuildContext`, and `Locale` references.
The only user-facing localization dependency was
`lib/application/resource_library/edit_drafts.dart`:

- Removed its `AppLocalizations` import and localized fallback strings.
- Added the stable `WorldviewModuleType` enum and key-to-type mapper.
- Moved the final label mapping into `lib/screens/resource_library/worldview_tab.dart`.
- Unknown persisted keys remain unchanged in the UI.

The remaining scan hits are comments describing locale-neutral diagnostics and
are not runtime localization dependencies. Application/domain/service UI
localization dependencies: **0**.

## Terminology Matrix

| Concept | zh-Hans | zh-Hant | en | ja | ko |
| --- | --- | --- | --- | --- | --- |
| Resource | 资源 | 資源 | Resource | リソース | 리소스 |
| Resource Library | 资源库 | 資料庫 | Resource Library | ライブラリ | 자료실 |
| Resource Studio | 资源工作室 | 創作工作台 | Resource Studio | リソーススタジオ | 리소스 스튜디오 |
| Worldview | 世界观 | 世界觀 | Worldview | 世界観 | 세계관 |
| Character Card | 角色卡 | 角色卡 | Character Card | キャラクターカード | 캐릭터 카드 |
| NPC Card | NPC 卡 | NPC 卡 | NPC Card | NPC | NPC 카드 |
| Scene | 场景 | 場景 | Scene | シーン | 장면 |
| Section | 章节 | 章節 | Section | 章 | 섹션 |
| Part | 段落 | 段落 | Part | パート | 파트 |
| Revision | 版本 | 版本 | Revision | リビジョン | 리비전 |
| Assembly | 组装 | 組裝 | Assembly | 組み立て | 조립 |
| Adventure | 冒险 | 冒險 | Adventure | 冒険 | 모험 |
| Session | 会话 | 會話 | Session | セッション | 세션 |
| Generation / Regenerate | 生成 / 重新生成 | 生成 / 重新生成 | Generation / Regenerate | 生成 / 再生成 | 생성 / 재생성 |
| Validation / Readiness | 验证 / 就绪 | 驗證 / 就緒 | Validation / Readiness | 検証 / 準備状態 | 검증 / 준비 상태 |
| Autosave / Conflict | 自动保存 / 冲突 | 自動儲存 / 衝突 | Autosave / Conflict | 自動保存 / 競合 | 자동 저장 / 충돌 |
| History / Trash | 历史记录 / 回收站 | 歷史記錄 / 回收站 | History / Trash | 履歴 / ごみ箱 | 변경 기록 / 휴지통 |
| Import / Export | 导入 / 导出 | 匯入 / 匯出 | Import / Export | インポート / エクスポート | 가져오기 / 내보내기 |
| Prompt / Model / Provider | 提示词 / 模型 / 服务商 | 提示詞 / 模型 / 服務商 | Prompt / Model / Provider | プロンプト / モデル / プロバイダー | 프롬프트 / 모델 / 제공자 |
| Reasoning / Context | 推理 / 上下文 | 推理 / 上下文 | Reasoning / Context | 推論 / コンテキスト | 추론 / 컨텍스트 |
| Inventory / Skill / Status / Timeline | 背包 / 技能 / 状态 / 时间线 | 背包 / 技能 / 狀態 / 時間線 | Inventory / Skill / Status / Timeline | インベントリ / スキル / ステータス / タイムライン | 인벤토리 / 스킬 / 상태 / 타임라인 |

## English QA

- Reviewed the core resource, generation, readiness, and editor strings.
- No high-confidence grammar, placeholder, or software UI wording defect was found.

## Traditional Chinese QA

- Fixed the simplified character in `reasoningEffortLow`: `极速` → `極速`.
- Aligned two high-visibility save/configuration strings with the established
  Traditional Chinese vocabulary: `保存` → `儲存`, `配置` → `設定`.
- No placeholder or ICU structure changed.

## Japanese QA

- Replaced nine direct Chinese `資料庫` remnants with natural `ライブラリ` wording.
- Replaced five direct Chinese `推演` remnants with `生成` or `推論` according to context.
- Checked core resource, readiness, generation, and editor terminology for
  natural UI wording and consistent polite style.

## Korean QA

- Reviewed the core resource, generation, readiness, and editor strings.
- No high-confidence untranslated Chinese text, placeholder defect, or obvious
  UI grammar issue was found.

## Simplified Chinese Consistency

The simplified Chinese files remain the semantic reference for the six-locale
set. Dynamic user content such as names, titles, provider/model names, file
names, and imported text remains untouched.

## Placeholder / ARB Parity

Validated all six ARB files:

- 1,501 message keys in each locale.
- 405 metadata entries in each locale.
- 0 missing keys and 0 extra keys.
- 0 placeholder mismatches.
- All ARB files parse as JSON and contain no empty message values.

## Responsive Risk Review

The translation fixes shorten or preserve existing labels. No button, tab,
dialog action, status badge, or input constraint was expanded. Existing resource
library widget coverage includes a 320 px viewport and wide desktop coverage.

## Tests

- `dart format --output=none --set-exit-if-changed .` — PASS
- `flutter gen-l10n` — PASS
- `flutter analyze` — PASS (`No issues found`)
- Targeted readiness, resource generation, and resource library tests — PASS (39 tests)
- `flutter test -r compact` — PASS (2,194 records, 1 skipped)
- `git diff --check` — PASS

## Remaining Findings

- BLOCKER: none
- MAJOR: none
- MINOR: none
- INFO: Some legacy UI wording remains intentionally unchanged because it is
  established product terminology or would require broad low-confidence copy
  editing outside this task.

## Status

READY_FOR_FINAL_I18N_ACCEPTANCE
