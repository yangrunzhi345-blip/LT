# ADR-0003：可配置的全局与项目级 AI 生成弹性预算

状态：Accepted（随 `feat/configurable-generation-elasticity` 实施）
基线：PR #5 合并后 main（cea474d）。PR #5 引入固定 20% 弹性：`C = min(floor(T × 1.20), A)`。

## 目标

1. 全局默认弹性比例可配置（0–50%，默认 20%，步进 5%）。
2. 资源项目（世界观 / 角色卡 / NPC）与冒险项目可独立覆盖或继承全局。
3. 生成任务开始时冻结预算快照，后续设置变化不追溯。
4. 保留 PR #5 全部语义与安全机制。

## 决策

### D1 配置载体（最小迁移）

| 层级 | 载体 | 说明 |
| --- | --- | --- |
| 全局默认 | `settings` 表键 `generation_elastic_percent`（int，默认 20） | 经 `SettingsProvider` 读写；DB 是 confirm 时权威读取处 |
| 资源覆盖 | `resources.metadata_json` 键 `generationElasticPercent`（int，缺失 = 继承） | 复用现有 metadata 列；`ResourceMetadataPolicy` 对小整型键天然放行 |
| 会话运行级选择 | `resource_creation_sessions.origin` 信封新增 `elastic_percent` 字段 | 复用 ADR 冻结的 origin 列编码（`ResourceCreationOriginEnvelope`），零新列 |
| 任务快照 | `resource_blueprints.elastic_percent`（INTEGER 可空，NULL = 历史固定 20%） | v49 迁移 `safeAddColumn`；confirm 事务内写入并冻结 |
| 冒险覆盖 | `AdventureConfig.generationElasticPercent`（int?，null = 继承） | 存于 `adventures.config` JSON，无需迁移 |

不新建平行“项目”体系：资源项目 = 资源行（resource_id），冒险项目 = adventure 行。关联角色生成只读取**目标资源自身**的覆盖，不读取参考角色/世界观覆盖。

### D2 解析优先级（confirm 冻结时）

```
effectivePercent =
    creationSession.origin.elasticPercent        // 本次运行的显式选择
 ?? targetResource.metadata.generationElasticPercent // 目标资源的持久覆盖
 ?? settings.generation_elastic_percent           // 全局默认（缺省 20）
```

历史 blueprint（`elastic_percent IS NULL`）一律按 20% 解析——与升级前固定行为逐位一致，历史任务不因全局值变化获得新预算。

### D3 预算计算（整数运算）

```dart
C = min((T * (100 + E)) ~/ 100, A)   // 纯整数 floor，无浮点误差
```

`GenerationBudgetPolicy.cumulativeCeiling` 增加命名参数 `elasticPercent`（默认 20，越界抛 ArgumentError，fail-closed）。常量 `elasticRatio`（double 0.20）移除，以 `defaultElasticPercent = 20` 取代。

### D4 快照冻结点

- **资源管线**：`confirmBlueprint`（同一事务创建 tasks）时解析并写入 `resource_blueprints.elastic_percent`。`remainingBudget` 与 `commitPartContent` 两个消费点经 `_cumulativeCeilingInTransaction` 统一读取冻结值。重启恢复（`recoverInterruptedTasks`）不重写预算 → 快照自动存活。
- **冒险对话**：回合开始 `_freezeSceneContext` 解析 `override ?? global` 并写入 `SceneDialogueContextSnapshot.budget`；多幕循环、长度守卫、溢出收敛、PromptBuilder 全部消费快照预算（PromptBuilder 增加显式 `outputBudget` 参数，消除其独立的二次 resolve）。

### D5 冒险对话 L0–L5 结合方式

档位自带 min/target/max 结构，直接把 `target × (1+E)` 作为新上限会**收窄**部分档位（如 L2 target=700 < max=1000）。因此采用**只放宽不收窄**：

```
effectiveHardMax = max(legacyHardMax, (target × (100 + E)) ~/ 100)
recommendedTokens = max(base.recommendedTokens, ceil(effectiveHardMax × 1.6) + 512)
```

- E = 0%：与旧行为逐位一致（无收窄）。
- E = 20%（默认继承）：L1 由 300 → 312（唯一变化，+12 字），其余档位不变 → 旧存档升级后行为基本不变。
- E = 50%：L0 150 / L1 390 / L2 1050 / L3 2400 / L4 4800 / L5 10000（L5 因 target×1.5 < max 不变）。
- quick 模式预算保持固定，不放宽。
- 下限（min）、目标（target）、`min*3` 不变量、多幕规划（`planStage`）、结算 token 上限（1024）全部不变；选项/状态 JSON 与正文计量继续分离（`---JSON---` 分割 + `ChineseCharacterCounter`）。

### D6 覆盖矩阵（生成入口 × 弹性接入）

| 生成入口 | 管线 | 本任务处理 |
| --- | --- | --- |
| 统一资源创建（世界观/角色卡/NPC）+ Blueprint Part 生成 | 统一管线 | 接入（冻结列 + 两消费点） |
| 关联角色生成 | 统一管线 | 自动继承（无独立适配点） |
| 场景批量导入（角色/NPC） | 统一管线 | 自动继承；NPC 独立 1500–3000 限制不变 |
| 失败 Part 重试 / 手动重生成 / 崩溃恢复 | 统一管线 | 快照存活，自动继承 |
| 详细世界观（遗留 AiGeneratorService 补充循环） | 独立管线 | **不接入**：其为下限-only（≥T）收敛循环，无累计上限语义；持久化侧 `ResourceIntegrityValidator`（≤50000 nominal）继续把关。接入需重造上限语义且该路径生产入口已收敛至 Studio；记录为已知边界 |
| 详细角色卡（遗留 stage 流程） | 独立管线 | **不接入**：生产编辑器已路由至 Resource Studio（`character_card_edit_page.dart:406-426`），遗留路径无 lib 调用方；结构完整性守卫（`CharacterCardGenerationGuard`）与 24000 绝对校验不变 |
| 冒险序章 | 结构化 JSON（scene+options），无正文预算 | **不接入**：无正文长度预算可言，弹性语义不适用 |
| 压缩 / 回合结算 / 信息提取 | 结构化输出 | **禁止接入**（输出越界 fail-closed，与本任务无关） |
| 冒险对话 L0–L5 / 多幕 | 冻结快照 | 接入（D5） |

### D7 不变量（不削弱）

SQLite 原子提交、CAS、attempt/Part ID 绑定、NDJSON 严格解析、有限重试、已保存正文不覆盖、不可变版本历史、压缩显式采纳、冒险就绪检查、4096 Part token 上限、3000 字 Part 上限、绝对容量（60000/24000/24000）、容量状态由 A 决定、结构化 JSON 完整性、多角色关系权威——全部保留，未放宽任何一项。

## 数据迁移（v48 → v49）

```dart
if (oldVersion < 49 && newVersion >= 49) {
  await safeAddColumn(db, 'resource_blueprints', 'elastic_percent', 'INTEGER');
}
```

同时更新 `createResourceBlueprintSchema` DDL（全新安装）。可空列、不写旧行、幂等、失败有 `.backup.v$oldVersion` 整库备份。旧数据四类语义：无覆盖旧项目 = 继承全局；固定 20% 历史任务 = NULL 冻结列按 20%；新建继承项目 = 实时全局；显式覆盖项目 = 各自值。

## 测试策略

纯函数矩阵（0/5/20/35/50 × 边界 C/C+1）、SQLite 迁移与冻结回归、对话档位新旧对照表、SettingsProvider 持久化、Widget（设置区 / 创建页 / Studio 摘要，320px viewport）、既有聚合预算测试扩展。真实付费 API 不自动触发（保留环境变量门禁）。
