# Slim Setting Cards — MAJOR（M1–M5）修复实施规格

- 基线：`refactor/slim-setting-cards` @ `04e1bfb`
- 范围：M1–M5 与直接耦合的收口；不恢复 `resources` 树 / revision / DAG；不改 `pubspec.yaml`；不 push
- 暂不纳入：NPC 批量生成、英文标题中文化、取消按钮底层流中断
- 验收模式：Integrated Single-Agent Full-Cycle + 独立只读 Review

## 关键核查结论（Phase 0）

1. **entries_json 的 adventureId=0 不会落库为 world entry**：`adventure_provider` 在创建冒险时用真实 `id` 调用 `WorldviewSnapshotService.buildManagedEntries(id, snapshot)` 再 `addWorldEntry`；快照内的 `entries_json` 只是持久化 config 副本，运行期无消费者。**无需改代码**，补一条回归测试固定该约定。
2. **关系表端点校验只认 `resources` 表**：`CharacterRelationshipRepositoryImpl._validateEndpoints` 要求两端为 live 的 character/npc `resources` 行；`listForResource` 也 INNER JOIN `resources`。原生设定卡（`sc_*`）不在该表，必须扩展为同时接受 `setting_cards`，否则 M2 只对迁移卡有效。
3. **TrackedStateLibraryRuntime 只读旧表**：需要注入 `SettingCardRepository`，把卡片解析出的 `tracked_state_definitions` 合并进 `load()`；`loadOwnerRow` 对卡片返回合成行，编辑页通过桥接写回卡片 metadata/content。
4. `SettingCardService.create/createFromType` 已支持 `originWorldviewId`（B1 完成），M2 只需创建页透传。

## 锁定的接口

### `SettingCardService`（M3）

```dart
static const String previousSnapshotKey = 'previous_content_snapshot';

/// 生成覆盖前保存最近 1 条旧稿（content/summary/saved_at，附带旧 structured_payload/detail_json）。
/// 无旧正文时不写。
Future<SettingCard> generate(...); // 行为扩展，签名不变

/// 恢复最近 1 条旧稿；无快照返回 null；恢复后删除快照（只能撤销一级）。
Future<SettingCard?> restorePreviousSnapshot(String id);

/// 仅当卡片正文为空且存在时软删除；用于创建页首轮生成失败清理孤儿卡。
Future<void> discardEmptyDraft(String id);
```

元数据快照结构：
```json
{
  "content": "...",
  "summary": "...",
  "saved_at": "...",
  "structured_payload": {},   // 若有
  "detail_json": {}           // 若有
}
```

### `SettingCardTrackedStateBridge`（M5，新增）

```dart
final class SettingCardTrackedStateBridge {
  const SettingCardTrackedStateBridge({required SettingCardRepository repository});
  Future<List<TrackedStateDefinition>> read(String cardId);
  Future<SettingCard?> write(String cardId, List<TrackedStateDefinition> definitions);
}
```

- 读：character/npc 用 `SettingCardMarkdownParser.resolveStructuredPayload` 的 `tracked_state_definitions`；worldview 优先 `metadata.detail_json.tracked_state_definitions`，再 structured_payload。
- 写：更新 `metadata.structured_payload.tracked_state_definitions`；worldview 同步 `metadata.detail_json.tracked_state_definitions`；同时在正文追加/替换 `## tracked_state_definitions` JSON 围栏；`repository.save`。

### `CharacterRelationshipRepositoryImpl`（M2）

- `_validateEndpoints`：资源行缺失/类型不符/已删时，回退查询 `setting_cards`（`kind in ('character','npc')` 且未删）。
- `listForResource`：不再 INNER JOIN `resources`，改为取候选边后用批量 endpoint 活跃性检查（resources + setting_cards），保持只返回 character/npc 边。
- 现有行为与错误码不变。

### `CharacterRelationshipManagement`（M2）

```dart
Future<CharacterRelationship> createFromPerspective({
  required ResourceId subjectResourceId,
  required ResourceId counterpartResourceId,
  required CharacterRelationshipType relationType,
  required String subjectRole,
  required String counterpartRole,
  String description = '',
});
```

### `SettingCardRelationshipsSection`（M2，新增 Widget）

- 入参：`SettingCard card`。
- 列表：`characterRelationshipManagementProvider.listFor(ResourceId(card.id))`，显示对方名称/关系/角色/描述，可删除。
- 添加：选择对方角色/NPC 卡（排除自身）、关系类型、双方角色、描述；`WorldviewCharacterScopePolicy.compatibility(counterpart.originWorldviewId, card.originWorldviewId) == crossWorld` 时禁止并提示。
- 仅 character/npc 卡渲染。

### `TrackedStateLibraryRuntime`（M5）

- `ProductionTrackedStateLibraryRuntime` 构造新增 `SettingCardRepository cards`。
- `load`：旧表条目 + 卡片条目（按 `card.mode` 过滤），按 resourceId 去重（旧表优先）。
- `loadOwnerRow`：旧表命中优先；否则返回合成行 `{id,name,setting_card_id,json_data,updated_at}`。

### `ResourceTrackedStateEditPage`（M5）

- 若 row 含 `setting_card_id`：通过 `SettingCardTrackedStateBridge` 读写；否则保留现有 draft + ResourceCrudController 路径。

## 阶段与文件边界

| Owner | 文件 |
| --- | --- |
| 主 Agent Phase 0/2 | 规格、`SettingCardCreatePage`、`SettingCardDetailPage`、目标字数/世界观选择/恢复按钮、ARB、`riverpod_providers.dart`、集成 Widget 测试 |
| Agent A | `setting_card_service.dart`、`setting_card_service_test.dart` |
| Agent B | `adventure_wizard_ai_drafts.dart`、wizard 步骤/面板文件、wizard 测试 |
| Agent C | 关系仓库、`character_relationship_management.dart`、`setting_card_tracked_state_bridge.dart`（新）、`tracked_state_library_runtime.dart`、`resource_tracked_state_edit_page.dart`、`setting_card_relationships_section.dart`（新）、对应测试 |

## 验收

- M1：创建/重生成面板可选默认/精简/详细并透传 target；详情页恢复按钮可用。
- M2：原生卡之间可创建/删除关系；跨世界观被阻断；关系可被 `listForResource` 读回。
- M3：重生成前快照只保留 1 条；恢复后内容/摘要/结构化载荷回到旧值；无快照返回 null；创建失败孤儿卡不可见。
- M4：Wizard 生成后自动选中并回填；详细开关真实生效；生成中按钮禁用并显示进度文本。
- M5：卡片定义出现在检测项目列表；卡片行可编辑并写回卡片；旧表路径不回归；entries_json 占位不落库有测试固定。
- 测试：新增单测 + Widget 测试；`flutter analyze` 0 error/0 warning；`dart format --set-exit-if-changed`；`git diff --check`。
