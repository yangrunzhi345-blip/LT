# 角色管理 UI 与运行时在场状态断链 — 根因分析与修复方案

- 状态：**待执行**（本报告只做调查与方案，未修改任何生产代码）
- 作者：claude-opus-5.5
- 日期：2026-09-27
- 报告基线：HEAD `4f5cd16593b000062a941241a54e3b7b34470264`（= `origin/main`，分支 `main`）
- 分析对象：工作区未提交改动中的角色管理相关文件

> 本文档是交接规格，不是完成报告。所有结论均来自对当前磁盘工作区代码的只读审查，
> 行号对应当前工作区内容。**尚未执行任何修复、未运行任何测试、未创建提交。**

---

## 1. 背景与问题陈述

本次任务是修复“角色管理 UI 不完整、添加角色与运行时状态分离、入口难以发现”的前端缺陷。
上一个 Agent 已在工作区完成一版实现（`scene_character_management_page.dart` 重写、
`quick_menu.dart` 菜单收敛、`runtime_state_hub_page.dart` 增加 `openCharacters` 入口、
新增 13 个 `characterManagement*` 文案键），但审查发现该版实现存在若干**看似完成、实际断链**的缺陷。

本报告聚焦其中最具结构性的一条主线：**角色管理页的“在场/离场”判定与全应用既有的场景在场权威
不在同一套 ID 空间上**，由此派生出错误的分类、可点击的无效操作、以及身份重复注册的风险。
同时记录另外三处独立的次级缺陷（导航环路、运行时摘要标签泛化、两处过时测试断言）。

---

## 2. 权威层事实（修复必须遵守的不变量）

在讨论缺陷前，先固定当前代码已经建立的权威边界。这些是**读取依据**，不是可协商项：

| 事项 | 权威 | 位置 |
| --- | --- | --- |
| 场景在场角色 | `SceneState.presentCharacterIds` | `lib/models/scene_state.dart:183` |
| 主角的在场标识 | 字面量 `'protagonist'` | `lib/models/scene_state.dart:192`（默认值） |
| 在场变更合法性 | `SceneStateProposalValidator` | `lib/services/scene_state_proposal_validator.dart:20-85` |
| 运行期实体的身份键 | `AdventureCharacterIdentity.effectiveId` | `lib/application/adventure/adventure_character_identity.dart:22-26` |

其中 `ScenePresence.participantIds` 是**派生投影**，不是权威（`adventure_repository_impl.dart:2012-2016`
在读取项目状态时就地重建 actorId 与 participantIds）。因此本方案的任何修法都不得反向依赖它。

### 2.1 权威层的一侧：主角存的是 `'protagonist'`

三处独立证据表明权威层的主角标识是字面量，而非角色卡 ID：

1. `lib/models/scene_state.dart:192` — `SceneState` 构造默认 `presentCharacterIds = const ['protagonist']`。
2. `lib/providers/adventure_provider.dart:313` 与 `:835` — 创建/引导冒险时以 `const ['protagonist']` 作为种子。
3. `lib/services/scene_state_proposal_validator.dart:54` — 校验结束时**无条件**执行 `present.add('protagonist')`；
   且在 `:44-47` 明确拒绝任何让 `'protagonist'` 离开场景的提案（`characters_leave:protagonist`）。

Repository 侧同样处处兼容两种写法，说明这是**已知的 ID 空间不一致**，而非某一处漏写：
`adventure_repository_impl.dart:1943-1945`、`:1966-1968` 使用 `entityId == protagonistId || entityId == 'protagonist'`；
`:2012` 的 fallback 也是 `const ['protagonist']`。

### 2.2 名册层的一侧：主角行存的是真实角色卡 ID

`AdventureSelectedCharacter` 由组装流程写入，主角行的键是**真实角色卡 ID**：

- `lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart:1537` — `_composeSelectedCharacters` 写 `id: c.id, characterId: c.id`。
- `lib/features/adventure/presentation/assembly/.../assembly_create_page.dart:248` — `_buildCurrentConfig` 同样处理。
- `lib/application/adventure/adventure_character_identity.dart:22-26` — `effectiveId` 优先返回 `characterId`，因此主角行的 `effectiveId` 就是角色卡 ID。
- 仅**历史数据**才可能出现 `legacy_protagonist`（`adventure_config.dart:624-635` 的旧版回退主角）。

### 2.3 结论：两套 ID 空间在主角这一点上交汇但互不相等

`'protagonist'`（权威）≠ `<主角角色卡 ID>`（名册 `effectiveId`）。
任何“用名册 ID 去 `presentCharacterIds` 里查表”的写法，对主角**必然恒为 false**。

---

## 3. 根因分析

### 3.1 [Blocker] 主角身份分裂导致分类错误与重复入場

**症状**：`SceneCharacterManagementPage` 打开后，主角被列在“已加入冒险”区段（而非“当前在场”），
并带有一个**可点击**的“进入场景”按钮；点击后会尝试把角色卡 ID 作为场景中的第二个实体加入。

**根因代码**（`lib/features/adventure/presentation/session/screens/scene_character_management_page.dart:75-82`）：

```dart
final presentIds = provider.sceneParticipantIds.toSet();   // 权威：含 'protagonist'
...
for (final character in characters) {
  final id = AdventureCharacterIdentity.effectiveId(character);  // 主角：角色卡 ID
  (presentIds.contains(id) ? present : away).add(character);     // 恒为 false
}
```

**为什么不会被下游拦住**：即便用户点击了“进入场景”，`adventure_repository_impl.dart:1517` 构建的
`knownCharacterIds` 同时包含字面量 `'protagonist'` 与 `selectedCharacters` 的 `characterId`，
主角卡 ID 属于“已知角色”，`scene_state_proposal_validator.dart:39-41` 不会报
`characters_enter:forbidden`。于是校验通过，场景里出现**同一角色的两个身份**
（`'protagonist'` + 卡 ID），运行期实体、overlay 与提示词会挂到不同身份上——
这正是 `adventure_character_identity.dart` 文档注释所警告的“状态定义与运行期覆盖值挂到不同身份”。

**连带影响**：`_lifeStatus` / `_runtimeSummary` 依赖 `_runtimeEntity`（`:271-284`）按 `candidateIds` 查实体，
而 `adventure_provider.dart:387-424` 的 `_seedCharacterRuntimeEntities` 在 `selectedCharacters` 非空时
**只以 `effectiveId`（卡 ID）播种**，不会播种 `'protagonist'`。因此主角行的生命周期状态在管理页
通常会落到 `null` → 显示“未知”，进入按钮也因此被 `canEnter` 关掉——
**UI 表面“少了入口”，实际是身份对不上**。

**旧版对照（HEAD 版本）**：`git show HEAD:.../scene_character_management_page.dart` 显示上一版曾用
`deadIds` 集合与 `available = !present.contains(id) && !character.isProtagonist` 做过主角特判。
新版重写时丢掉了这层保护，回归由此产生。

### 3.2 [Major] 管理页 ↔ 运行时状态中心 形成无界 push 环路

**根因代码**：

- 管理页卡片点击：`scene_character_management_page.dart:195-199` → `RuntimeStateHubPage(openCharacters: true)`
- Hub 内管理入口：`runtime_state_hub_page.dart:823-838` → 当 `types.contains(RuntimeEntityType.character)` 时渲染
  `AppCard + FilledButton.icon(label: l10n.characterManagementManage)` → push `SceneCharacterManagementPage`

从 Chat 页进入 Hub 时该入口是**必要**的（“入口难以发现”正是本次要修的缺陷），
但从管理页进入 Hub 后仍渲染它，就会形成可无限叠加的导航栈。
`openCharacters` 字段（`:30-32`、`:58`）已经承载了“从管理页进入”这一信号，可直接复用作抑制条件。

### 3.3 [Major] 运行时摘要把所有未映射 overlay 键泛化为同一个标签

**根因代码**（`scene_character_management_page.dart:319-329`）：

```dart
for (final entry in entity.overlay.entries) {
  if (preferred.contains(entry.key) || ...) continue;
  values.add(
    '${l10n.runtimeStateChangedState}: '            // 恒定「状态变化」
    '${RuntimeStatePresentation.valueLabel(entry.key, entry.value, l10n)}',
  );
}
```

除 `preferred` 白名单（hp/mp/gold/relationship/affinity/energy/level）之外的一切 overlay 键——
包括用户在冒险中定义的**自定义属性**——都被标成同一个词“状态变化”，
用户无法分辨“体力”和“声望”的差别。项目已有正确的解析器却未被使用：

- `RuntimeStatePresentation.fieldLabelWithMetadata(path, l10n, {customAttributeLabels})`（`runtime_state_presentation.dart:65-77`）
- `RuntimeStatePresentation.customAttributeLabels(config?.allTrackedCustomAttributes ?? const [])`（`:79-87`）

另需注意：`fieldLabel`（`:33-63`）的 switch **没有 `'gold'` 分支**，会落到
`runtimeStateFieldUnknown`。因此 `:315` 现有的 `path == 'gold' ? l10n.characterManagementGold : ...`
特判**必须保留**，不能简单替换为 `fieldLabelWithMetadata`。

### 3.4 [Minor] 两处测试断言已过时

`test/widget/custom_attribute_test.dart`：

- `:444` — `expect(find.text(zh.sceneCharactersTitle), findsOneWidget);`
  该断言对应已被**有意移除**的 `scene_characters` 快捷菜单项（见 `lib/screens/chat/widgets/quick_menu.dart:55-97`，
  现仅剩 inventory / skills(角色管理) / word_count / settings）。菜单收敛是本任务的既定目标，
  断言应改为 `findsNothing` 以固化新契约。
- `:482` — `expect(find.text(zh.characterManagementTitle), findsOneWidget);`
  位于 `CharacterStatusScreen renders as full-screen Scaffold with tabs`。
  该 Screen 的 AppBar 标题是 `title: Text(l10n.characterStatusTitle)`
  （`lib/screens/chat/widgets/character_sheet.dart:1111-1112`，`app_zh.arb:1871` = “角色状态”）。
  上一版 Agent 误改成了角色管理的文案，应**还原**为 `zh.characterStatusTitle`。

### 3.5 [Minor] 自引用的超长导入路径

`scene_character_management_page.dart:4-6` 使用了从仓库根起算的自引用路径：

```dart
import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../../../../features/adventure/presentation/state/runtime_state_hub_page.dart';   // ← 穿越 features 自身
import '../../../../../features/adventure/presentation/state/runtime_state_presentation.dart';
```

其中第 5、6 行存在 `features/adventure/.../features/adventure/...` 式的自引用回环，
应改为同层相对路径（`../../state/runtime_state_hub_page.dart` 等），
与同目录其他文件的导入风格一致。

### 3.6 [待评估] “可加入当前场景的角色”缺少独立区段

任务要求明确区分“可加入当前场景的角色”。当前实现把不在场的角色与**无法进入**的角色
（`isDead` / `isUnknown`）混在同一个“已加入冒险”区段里，
且被 `onPressed: null` 禁用的进入按钮**不给出任何原因提示**。
用户看到的是“按钮灰了但不知道为什么”，属于“UI 看似完成但实际断链”。

---

## 4. 修复方案

> 以下为建议实施内容，**本次未执行**。所有改动限定在 Presentation 层、
> Widget 测试与 i18n 文案，不得触碰 SQLite schema / migration / Repository Authority /
> Domain 状态模型 / LLM / Prompt / Streaming / State Commit。

### 4.1 修复主角身份分裂（对应 §3.1）

**原则**：不在 Presentation 层新建第二套在场真相，只让读侧贴合既有权威。

1. **主角行恒定为在场**。在 `build` 的分类循环（`:79-82`）中，对 `character.isProtagonist == true`
   的行直接归入 `present`，不参与 `presentIds.contains(...)` 比对。
   依据：`scene_state_proposal_validator.dart:54` 无条件 `present.add('protagonist')`，
   主角在场景中是**不可变事实**而非可查询状态。
2. **非主角行用候选 ID 求交集**。把 `presentIds.contains(id)` 改为
   `AdventureCharacterIdentity.candidateIds(character).any(presentIds.contains)`，
   与 `_runtimeEntity`（`:275-279`）已有的查找口径保持一致，
   兼顾历史数据可能落在 `id` 或 `characterId` 任一侧的情况。
3. **主角行不提供进入操作**。`canEnter` 对主角恒为 `false`，
   并在 UI 上不渲染“进入场景”按钮（当前 `isInScene == true` 分支已因 `canLeave: false` 渲染 `null`，
   需确保分类修正后主角落入该分支）。
   依据：`addCharacterToScene('protagonist')` 会命中 `alreadyAttached`
   （`adventure_repository_impl.dart:2152-2156` 对 `attaching.isProtagonist` 直接 `rejected`），
   UI 不应提供必然失败的操作。
4. **不改动 `_seedCharacterRuntimeEntities` 的播种策略**。主角运行期实体缺失时
   `_lifeStatus` 返回 `null` 并显示“未知”，这是**诚实的表现**；
   擅自补默认 HP/MP/金币或按 UI 猜测存活状态属于明令禁止项。
   若需改善，应通过“未知”文案说明原因（见 §4.3），而非伪造数据。

**影响面**：`present` / `away` 两个列表的分类结果；
`AdventureCharacterIdentity.candidateIds` 已是既有公共方法，无需新增抽象。

### 4.2 断开导航环路（对应 §3.2）

在 `runtime_state_hub_page.dart:823-838` 的管理入口上增加条件：
仅当 `!widget.openCharacters` 时渲染该 `AppCard`。

- 从 Chat 页进入 Hub（`openCharacters: false`）→ 入口保留，满足“入口可发现”目标。
- 从管理页进入 Hub（`openCharacters: true`）→ 入口隐藏，导航栈不再叠加。

**备选方案**：管理页卡片点击改为 `Navigator.pop` 语义（若 Hub 已在栈中）。
不推荐——`openCharacters` 是显式构造参数，条件渲染更直观且不依赖栈结构。

### 4.3 修正运行时摘要标签并补足禁用原因（对应 §3.3、§3.6）

1. 在 `_runtimeSummary` 中计算一次
   `final labels = RuntimeStatePresentation.customAttributeLabels(config?.allTrackedCustomAttributes ?? const [])`，
   然后对未命中 `preferred` 的条目改走
   `RuntimeStatePresentation.fieldLabelWithMetadata(entry.key, l10n, customAttributeLabels: labels)`。
2. **保留 `'gold'` 特判**（`:315`）：`fieldLabel` 无 `'gold'` 分支。
3. 为被禁用进入按钮补充可读原因（如“已死亡”“状态未知”），
   并把“不在场且可进入”的角色拆到独立区段，使三种状态在视觉上可分辨。
   新增文案键时需同步 6 个 ARB 文件（en / ja / ko / zh / zh_Hans / zh_Hant）并重新生成
   `lib/l10n/generated/`。

### 4.4 清理导入路径（对应 §3.5）

把 `scene_character_management_page.dart:5-6` 的自引用绝对式相对路径改为同层相对路径。

### 4.5 修正测试断言（对应 §3.4）

- `custom_attribute_test.dart:444` → `expect(find.text(zh.sceneCharactersTitle), findsNothing);`
- `custom_attribute_test.dart:482` → 还原为 `expect(find.text(zh.characterStatusTitle), findsOneWidget);`

---

## 5. 测试要求

修复后至少覆盖以下场景（沿用 `test/helpers/` 或 `test/widget/responsive/` 现有 viewport helper）：

1. **身份分类**：主角出现在“当前在场”区段，且**不渲染**进入按钮。
2. **真实 mutation 投影**：点击配角“进入场景”后，**重新读取权威**
   （`SceneState.presentCharacterIds` 或页面上重新投影的在场标记）确认其确实改变；
   不得只验证 `find.text()`。
3. **主角不可重复入場**：确认不存在任何路径能对主角发起 `addCharacterToScene`。
4. **导航环路**：从管理页进入 Hub → Hub 不渲染管理入口；
   从 Chat 页进入 Hub → 管理入口仍存在。
5. **摘要标签**：自定义属性显示其定义名而非“状态变化”；`gold` 仍显示“金币”。
6. **响应式硬门槛**：`320×568`、`360×640`、`390×844`、`412×915`、`768×1024`、`1280×800`
   均无 `RenderFlex overflow`；含 `TextScaler 2.0`、暗色主题、超长角色名、
   多角色、以及**无运行时实体**（`_lifeStatus == null`）场景。

---

## 6. 明确不做（范围边界）

- **禁止**修改：SQLite schema / migration / Repository Authority / Domain 状态模型 /
  LLM / Prompt / Streaming / State Commit / 新的角色状态权威 / 新的 Presence Authority。
- **禁止**在 Presentation 层复制、缓存或推导第二套角色状态真相。
- **禁止**默认 HP=100 / MP=100 / 金币=0 冒充真实状态；禁止按 UI 猜测存活状态。
- **禁止**展示 `entityId`、内部 UUID、JSON、SQL、runtime key 或开发者内部字段名。
- **禁止**修改 `resource_library_production_test.dart` 或其生产流程，除非能证明当前 diff 确实导致该回归。
- 所有修改保持在 working tree，**不创建提交、不推送、不改动远端**。

---

## 7. 验收标准

全部满足方可判定为 `READY_FOR_COMMIT`（Git 写操作已被本轮约束禁止，故不写 `ACCEPTED`）：

1. §3.1–§3.6 各项缺陷已修复，且未引入新的 ID 空间。
2. `dart format --output=none --set-exit-if-changed .`、`git diff --check`、`flutter analyze` 全部通过。
3. §5 全部测试项通过，含至少一项**验证权威投影真实改变**的 mutation 断言。
4. 全量 `flutter test` 通过；若存在无法在本任务边界内修复的既有失败，
   须出具只读基线 worktree（`git worktree add --detach <tmp> HEAD`）对比证据，
   并按 A/B/C 分类，禁止为通过测试修改资源库生产流程。
5. 提交前 diff 审计按文件分类，显式添加本任务文件，禁止 `git add -A`。

---

## 8. 当前状态

| 项目 | 状态 |
| --- | --- |
| 本报告 | 已完成 |
| 生产代码修复 | **未执行** |
| 测试运行 | **未执行** |
| 提交 | **NO** |
| 推送 | **NO** |
| 远端改动 | **NO** |

已识别但尚未应用的全部修复项：§4.1（Blocker）、§4.2（Major）、§4.3（Major + 待评估）、
§4.4（Minor）、§4.5（Minor）。

---

*报告撰写：claude-opus-5.5*
