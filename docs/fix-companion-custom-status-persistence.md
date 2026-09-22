# 修复报告：非主角自定义检测状态无法持久化

- 基线：`970491f`（`origin/main`）
- 提交：`c6c367a fix(adventure): persist companion detection statuses by stable id`
- 范围：correctness 修复，无 UI 重做、无数据库 migration、无 schema 变更

## 1. Root Cause

主角状态写在 `AdventureConfig.customAttributes` 上，保存时是 `config.copyWith(...)`，不依赖命中任何已有对象，因此一直可用。

非主角状态写在 `SupportingCharacter.customAttributes` 上，而保存路径 `_saveDetectedStatuses()` 假设同伴对象**已经**存在于 `config.supportingCharacters`：

```dart
config.supportingCharacters.map((c) {
  if (c.id == companion.id || c.name == companion.name) { ... }
  return c;
})
```

但新版组装流程（`assembly_create_page.dart`）创建冒险时只填 `selectedCharacters`，`supportingCharacters` 为空；`character_sheet.dart` 为了让这些角色可见，会在 `build()` 里临时 `new` 一个 `SupportingCharacter` 仅用于展示。对这个临时对象来说 `map()` 零命中，`updatedChars` 等于原列表，写回的 config 里根本没有该角色 —— 于是 UI 当下看似成功，返回页面后消失，`adventures.config` 从未落盘，`allTrackedCustomAttributes` / `RuntimeStateValidator` / `CustomStatusMerger` / Prompt 全都看不到。

附带问题：`c.name == companion.name` 让同名角色可能共用一份快照，串状态。

## 2. Data Flow Before

```
selectedCharacters（roster authority）
  → build() 临时 new SupportingCharacter（UI-only）
  → _saveDetectedStatuses: supportingCharacters.map(...)  ← 空列表，零命中
  → copyWith(supportingCharacters: 未变化)
  → updateAdventureConfig → adventures.config   ← 状态从未写入
```

## 3. Data Flow After

```
selectedCharacters（决定角色存在）
  → AdventureCharacterIdentity.effectiveId()
       characterId → selection id → SupportingCharacter.legacyIdFor(name|role)
  → AdventureCharacterStatusStore.writeCompanionCustomAttributes()
       命中   → copyWith（id 收敛到 effectiveId、customAttributes、affinity）
       未命中 → 追加 adventure-owned SupportingCharacter 快照
  → config.copyWith(supportingCharacters: ...)
  → chat.updateAdventureConfig
       → baselineForPersistence() 还原 runtime overlay（剧情值不写回 frozen baseline）
       → UPDATE adventures SET config = jsonEncode(...)
       → notifyListeners → UI 用新 config 重建
```

三层 authority 保持不变：`selectedCharacters` 管 roster，`SupportingCharacter` 快照管状态定义，`adventure_runtime_entities` 管运行值。没有新增第三套存储。

## 4. Modified Files

| 文件 | 目的 |
| --- | --- |
| `lib/application/adventure/adventure_character_identity.dart`（新） | 唯一身份规则：`effectiveId`、`candidateIds`、`hasStableId`、`resolveRelation`、`indexOfSupporting` |
| `lib/application/adventure/adventure_character_status_store.dart`（新） | 唯一持久化权威：绑定 `characterName`、同步 affinity、按 ID 定位快照、缺失时补建；名称匹配仅限「完全没有稳定 ID 的历史选择行」 |
| `lib/screens/chat/widgets/character_sheet.dart` | 重构 `_saveDetectedStatuses`；新增 `_selectedCharacterFor`；视图条目改用 `effectiveId`；移除 name authority |
| `lib/models/supporting_character.dart` | 抽出 `legacyIdFor(name, role)`，让 `fromJson` 与补建快照共用同一套确定性 ID 规则 |
| `lib/providers/adventure_provider.dart` | `_seedCharacterRuntimeEntities` 改用共享 `effectiveId`，与快照 ID 对齐 |

未改动：`adventure_config.dart`、`adventure_repository*.dart`、`runtime_state_validator.dart`、`custom_status_merger.dart`、`app_config.dart`、runtime resolver —— 静态审计确认它们本来就围绕同一结构工作。

## 5. Database

- 未修改 schema，未发生 migration，`schemaVersion` 不变。
- `AdventureRepositoryImpl.updateAdventureConfig()` 仍是 `UPDATE adventures SET config = jsonEncode(config.toJson())`。
- 同伴状态经 `SupportingCharacter.toJson()['custom_attributes']` 进入 `adventures.config` JSON。
- 剧情产生的运行值仍在 `adventure_runtime_entities.overlay['custom_attributes.<attrId>']`，落库前由 `baselineForPersistence()` 还原。

## 6. Tests

新增 `test/unit/custom_status_selected_character_persistence_test.dart`（13 例）：selected-only 添加（内存 → DB → reload → SQLite reopen 四段断言）、编辑、删除真实消失、文本状态、两个同名角色隔离、legacy 快照、主角 add/edit/delete/quick adjust、prompt tracking、validator 接受、ID 收敛、identity authority 3 例。

新增 widget 回归（`test/widget/custom_attribute_test.dart`，真实 ChatProvider + SQLite）：非主角通过 UI 添加并落盘；主角 UI 添加 + quick adjust。

`test/unit/custom_status_runtime_overlay_test.dart` 新增：已有 overlay 的角色再手工添加新属性后，旧属性 baseline 保持 frozen、effective 来自 overlay，新属性定义真实持久化。

**反证**：将 `character_sheet.dart` 临时还原到修复前，新的 selected-only 用例失败（无快照生成），主角用例仍通过 —— 确认锁定的是本 BUG。

## 7. Verification

- `flutter analyze` → No issues found
- `flutter test test/widget/custom_attribute_test.dart` → 19/19
- 指定三个单元文件 → 67/67
- 定向（adventure/character/runtime/custom_status/database/repository）→ 223/223
- 冒险/组装相关 widget → 97/97
- 全量 `flutter test` → 2157/2157 All tests passed
- `dart format` 0 变更；`git diff --check` 干净

## 8. Remaining Risks

1. **双 ID 历史兼容**：当前创建入口都写 `id == characterId`；旧库仍可能出现 `selected.id = A` / `characterId = B` 且快照落在 A 上。此时 store 会命中 A 并把 id 收敛到 B（与运行期实体一致），是一次有意的一次性重写；若有外部逻辑硬编码旧 id 需复核。
2. **Prompt 的 `character_id` 仍按名字反查**（`AppConfig._characterIdFor`）。`CustomAttributeItem` 没有 characterId 字段，因此两个同名角色**都**有同名状态时，两条状态都会解析到第一个匹配角色的 id。本次未改提示词协议（超出本 BUG 范围，会动到模型契约）；根治建议给 `CustomAttributeItem` 增加可选 `characterId`。
3. `selectedCharacters` 为空的纯旧冒险走 provider fallback 分支，行为不变。
