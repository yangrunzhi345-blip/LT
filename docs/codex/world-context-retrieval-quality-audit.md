# P1 — World Context Retrieval Quality Audit (世界观上下文检索质量审计报告)

## 1. 任务背景与审计目标

在 LT 项目的叙事上下文中，`WorldContextBuilder` 负责从冻结的世界观快照及条目库中召回与当前轮次对话最相关的规则（Constraints）、事实（Facts）与背景设定（Lore）。
本阶段目标并非盲目实现向量检索，而是通过量化指标和结构化自动化测试集，全面审计当前基于关键词与元数据的检索机制，确立其真实检索质量边界，厘清失败原因究竟属于“算法机制缺陷”还是“数据建模不全”，并基于量化事实给出是否引入 Hybrid Vector Retrieval（混合向量检索）的架构裁定。

---

## 2. 当前 World Context 检索架构审计

### 2.1 整体调用链

```
用户输入 (rawInput)
   │
   ├──> ContextOrchestrator.build(...)
   │       ├── 1. Intent & SceneState 解析与冲突判定
   │       ├── 2. 计算 ContextBudget 与 worldBudget ((inputLimit - mandatory) ~/ 4)
   │       ├── 3. 提取 location = conflict.sceneState.location
   │       ├── 4. 提取 characterNames (在场角色 + 输入提及角色)
   │       │
   │       └──> WorldContextBuilder.build(...)
   │               ├── 1. 构建 searchText = [query, location, ...characterNames].join(' ').toLowerCase()
   │               ├── 2. 遍历有效条目并去重 (_normalize)
   │               ├── 3. 分类判定 (_classify -> constraint, fact, lore)
   │               ├── 4. 关键词匹配 (entry.keys.where(searchText.contains))
   │               ├── 5. 相关性判定 (kind == constraint || sticky > 0 || matchedKeys > 0 || content.contains(location))
   │               ├── 6. 计分排序 (base + matchedKeys * 50 + sticky*25 - insertionOrder)
   │               └── 7. Token 预算贪心截断 (按 score 降序，非 constraint 条目超预算则裁掉)
   │
   └──> PromptCompiler.compile(...)
           ├── 世界硬约束 (context.world.constraints) -> 置顶于系统提示词
           ├── 当前相关角色 / 持久状态 / 场景状态
           ├── 本轮相关世界事实 (context.world.facts)
           └── 本轮相关世界背景 (context.world.lore)
```

### 2.2 核心机制详细分析

1. **查询文本（Search Text）构建**：
   - 源码：`final searchText = [query, location, ...characterNames].where((v) => v.trim().isNotEmpty).join(' ').toLowerCase();`
   - **特点**：将玩家原始输入文本（`query`）、场景当前地点（`location`）与相关角色名字（`characterNames`）按空格拼接并转小写。
   - **局限**：未进行任何中文分词、停用词过滤或标点剥离；检索依赖条目关键词作为子串出现在 `searchText` 中。

2. **Keys 命中机制**：
   - 源码：`final matchedKeys = entry.keys.where((k) => k.trim().isNotEmpty).where((k) => searchText.contains(k.toLowerCase())).length;`
   - **特点**：对条目元数据中的每一个 key，检查其是否为 `searchText` 的**字面子串**（`contains`）。
   - **局限**：
     - 若条目 key 为“魔法研究中心”，而玩家输入为“学习法术最厉害的地方”，则匹配数必然为 0；
     - `WorldEntry.matches` 中定义的 `useRegex` 正则匹配逻辑在 `WorldContextBuilder` 中**完全未被调用**。

3. **Location 参与机制**：
   - **双通道参与**：
     1. `location` 作为子字符串加入 `searchText`，参与 `matchedKeys` 计数；
     2. `isRelevant` 显式保障：`(location.isNotEmpty && entry.content.contains(location))`。
   - **局限**：
     - 只检查正文是否包含 `location` 字面。若当前地点为“白港外港码头”，而设定条目正文仅提及“白港”，则 `entry.content.contains("白港外港码头")` 为 `false`，缺乏层级包含解析。

4. **CharacterNames 参与机制**：
   - `characterNames` 注入 `searchText`。
   - **关键发现**：条目正文若提到角色（例如“暗杀组织曾收留刺客艾琳”），但该条目的 `entry.keys` 未显式收录角色名“艾琳”，则 `matchedKeys` 为 0，且 `isRelevant` **不会扫描正文中的角色名**。条目直接被判为 `irrelevant` 并过滤。

5. **Sticky 影响机制**：
   - `entry.sticky > 0` 会直接令 `isRelevant = true`，并在打分中赋予 `+25` 分。
   - **关键漏洞**：在 Token Budget 截断环节（`used + tokens > tokenBudget && item.kind != WorldContextKind.constraint`），**只有被分类为 `constraint` 的条目才享有预算豁免权**。被归类为 `fact` 或 `lore` 的 sticky 条目（例如快照中的“创作约束”），在预算吃紧时依然会被裁剪抛弃。

6. **Constraint / Fact / Lore 分类机制**：
   - `constraint`：`content.startsWith('【世界观/世界规则】') || entry.sourceType == 'rule'`
   - `fact`：`content.contains('【世界观/当前世界状态】') || content.contains('【世界观/locations】') || content.contains('【世界观/factions】') || entry.sourceType == 'location' || entry.sourceType == 'faction'`
   - `lore`：其余所有内容（包括 `概览`、`创作约束 creative_constraints`、`customs`、`timeline`、`glossary` 等）。
   - **问题**：`WorldviewSnapshotService` 生成的 `创作约束`（`creative_constraints`）虽带有 `sticky: 1`，但未以 `【世界观/世界规则】` 开头，被划为 `lore`（基础分仅 100），高压下易被抢占淘汰。

7. **Score 打分机制**：
   - 基础分：`constraint = 1000`，`fact = 500`，`lore = 100`；
   - 加分：`matchedKeys * 50`，`sticky > 0 ? 25 : 0`；
   - 减分：`- entry.insertionOrder.clamp(0, 100)`；
   - 排序：按 score 降序稳定排序。由于 Fact 基础分为 500，Lore 即使匹配 7 个关键词（100 + 350 = 450）也无法超越任意命中 0 个 key 但命中地点的 Fact（500 分）。

8. **Token Budget 限制行为**：
   - 预算来源于 `((budget.inputLimitTokens - mandatoryTokens) ~/ 4).clamp(128, 4096)`；
   - 遍历排序后的候选集，一旦 `used + item.estimatedTokens > tokenBudget`，记录 `filteredEntryReasons[id] = 'token_budget'` 并 `continue`（允许后续小 token 条目填补空隙）。

9. **Duplicate / Normalize / Filtered 行为**：
   - 归一化：小写 + 正则移除所有空白与中英文标点符号；
   - 去重：通过 `seen.add(normalized)` 检测，完全重复正文的后续条目被记录为 `'duplicate'` 并过滤。

---

## 3. 检索质量测试集设计

在 `test/support/world_retrieval_benchmark_fixtures.dart` 与 `test/unit/world_context_retrieval_benchmark_test.dart` 中构建了覆盖 12 大场景类型的确定性自动化 Benchmark 测试集（共 25 个独立测试用例），无任何外部模型与网络依赖：

| 序号 | 测试分类 | 代表用例描述 | 预期行为 |
|---|---|---|---|
| 1 | 精确关键词 | “银月城有什么特点？” / 势力“秘术议会”查询 | 100% 召回，精准匹配对应条目 |
| 2 | 关键词重组 | “北境的魔法研究中心在哪里？” / 倒装疑问句 | 100% 召回（多 key 独立命中累加） |
| 3 | 同义表达 | “我想去北方学习法术最厉害的城市” / “来路不正的黑货” | 考察 contains 缺陷，必然漏召回（FN） |
| 4 | 间接描述 | “那个聚集大量法师学者的北方城市” / 观星云端建筑 | 考察语义缺词情况下的表现，必然漏召回（FN） |
| 5 | 地点关联 | 场景地点为“白港”，查询不带地点 / 地点层级不匹配 | 精确地点正常召回；下级细分子地点引发断裂 |
| 6 | 角色关联 | 提到在场同伴“艾琳”且 key 完备 / 正文含角色但 key 缺失 | key 完备时召回；key 缺失时算法不扫正文导致漏召回 |
| 7 | Sticky / Constraint | 极低预算下的硬规则免裁剪 / 创作约束分类漏洞 | 纯规则条目 100% 保留；创作约束存在裁剪风险 |
| 8 | Fact / Lore 竞争 | 预算吃紧时，Fact (500分) 抢占预算，Lore (100分) 被淘汰 | 验证高权重 Fact 优先保留 |
| 9 | 无关内容 | 日常酒馆点酒指令与远古神话、深渊神教条目对照 | 100% 排除，True Negative |
| 10 | 相似但错误 | “暗月城”盗贼黑市 vs “银月城” / 通用 key（“城市”）污染 | 精确区分实体；揭示宽泛 key 引发的误召回（FP） |
| 11 | 别名/简称 | “帝都”未在 keys 中建立映射 vs 完整映射“帝都/王都/中央皇城” | 揭示当前机制对别名元数据建模的强依赖 |
| 12 | 中文表达变化 | 涵盖主语省略、代词指代（“那里”）、口语化、超短查询、长叙述查询 | 系统性评测各类中文语法变体下的召回表现 |

---

## 4. 评价指标与 Benchmark 测量结果

### 4.1 指标定义

- **Recall（召回率）**：$\frac{TP}{TP + FN}$（应召回且实际召回的比例）
- **Precision（准确率）**：$\frac{TP}{TP + FP}$（实际召回结果中真实相关的比例）
- **F1-Score**：$2 \times \frac{\text{Precision} \times \text{Recall}}{\text{Precision} + \text{Recall}}$
- **False Negative (FN)**：应召回但被系统过滤或漏掉的条目数
- **False Positive (FP)**：无关但被错误加入上下文的条目数
- **Token Waste**：由 False Positive 污染条目所消耗的估算 Token 总量
- **Constraint Retention**：硬约束规则在各类压力场景下的保留率（目标 100%）
- **Fact Retention**：相关世界事实在候选竞争与预算限制下的有效保留率
- **Lore Noise**：注入的背景条目中无关噪声条目的比例

### 4.2 测量汇总数据

执行测试套件 `test/unit/world_context_retrieval_benchmark_test.dart`，获得基线测量数据：

```
================================================================================
WORLD CONTEXT RETRIEVAL QUALITY BENCHMARK REPORT
================================================================================
Total Test Cases: 25
Overall Recall: 61.5% (16/26)
Overall Precision: 94.1% (16/17)
Overall F1-Score: 74.4%
True Positives (TP): 16
False Negatives (FN): 10
False Positives (FP): 1
True Negatives (TN): 11
Total Token Waste: 20 tokens
Constraint Retention: 100.0%
Fact Retention: 59.1%
Lore Noise: 50.0%
--------------------------------------------------------------------------------
CATEGORY BREAKDOWN:
  1. 精确关键词                     | Recall: 100.0% | Prec: 100.0% | TP: 2 FP: 0 FN: 0 | Waste: 0 tk
  2. 关键词重组                     | Recall: 100.0% | Prec: 100.0% | TP: 2 FP: 0 FN: 0 | Waste: 0 tk
  3. 同义表达                      | Recall:   0.0% | Prec: 100.0% | TP: 0 FP: 0 FN: 2 | Waste: 0 tk
  4. 间接描述                      | Recall:   0.0% | Prec: 100.0% | TP: 0 FP: 0 FN: 2 | Waste: 0 tk
  5. 地点关联                      | Recall:  50.0% | Prec: 100.0% | TP: 1 FP: 0 FN: 1 | Waste: 0 tk
  6. 角色关联                      | Recall:  50.0% | Prec: 100.0% | TP: 1 FP: 0 FN: 1 | Waste: 0 tk
  7. Sticky / Constraint       | Recall:  66.7% | Prec: 100.0% | TP: 2 FP: 0 FN: 1 | Waste: 0 tk
  8. Fact / Lore 竞争            | Recall: 100.0% | Prec: 100.0% | TP: 1 FP: 0 FN: 0 | Waste: 0 tk
  9. 无关内容                      | Recall: 100.0% | Prec: 100.0% | TP: 0 FP: 0 FN: 0 | Waste: 0 tk
  10. 相似但错误                    | Recall: 100.0% | Prec:  66.7% | TP: 2 FP: 1 FN: 0 | Waste: 20 tk
  11. 别名/简称                    | Recall:  50.0% | Prec: 100.0% | TP: 1 FP: 0 FN: 1 | Waste: 0 tk
  12. 中文表达变化                   | Recall:  66.7% | Prec: 100.0% | TP: 4 FP: 0 FN: 2 | Waste: 0 tk
================================================================================
```

---

## 5. 失败根因分类与归因

本次审计针对所有 11 个未达全召回/误判案例进行了严格根因归类，明确区分“检索算法问题”与“数据建模问题”：

```
--------------------------------------------------------------------------------
FAILURE REASON TAXONOMY:
  contains 机制无法理解同义/语义表达                  : 6 cases (54.5%)
  key 缺失 (别名/通用实体未建模)                     : 2 cases (18.2%)
  location 未命中或层级不匹配                      : 1 cases (9.1%)
  角色仅在正文出现但缺少 character metadata/key      : 1 cases (9.1%)
  分类 constraint/fact/lore 不准确 (创作约束被归为lore): 1 cases (9.1%)
--------------------------------------------------------------------------------
ISSUE TYPE CLASSIFICATION:
  检索算法问题                          : 7 cases (63.6%)
  WorldEntry 数据建模问题               : 4 cases (36.4%)
--------------------------------------------------------------------------------
```

### 5.1 检索算法核心问题（占 63.6%）

1. **同义表达与语义缺词崩溃（Recall = 0.0%）**：
   - 现象：当玩家输入不包含设定中的原词（如“法师学者”代替“魔法研究中心”，“整点硬家伙”代替“军备武器”），单纯的 `searchText.contains(key)` 必然命中 0 个词。
   - 结论：**纯字面匹配（Lexical Match）在叙事自由度较高的自然语言交互中存在不可逾越的硬天花板**。
2. **指代（Anaphora）与省略断裂**：
   - 现象：玩家使用“那里”、“那个地方”、“刚才那批人”时，字面检索完全失效。除非当前 `SceneState.location` 碰巧完全一致，否则历史对话中的实体指代无法被字面检索召回。
3. **地点层级缺失**：
   - 现象：`entry.content.contains(location)` 仅支持“包含场景全称”，不支持“场景全称为条目地点子串”。

### 5.2 数据建模核心问题（占 36.4%）

1. **快照生成器（`WorldviewSnapshotService`）关键词提取受限**：
   - 现状：`_keywords` 仅扫描 json 中少数字段并 `take(12)`，丢失大量别名、通称及文中角色实体。
2. **角色实体元数据缺失**：
   - 现象：条目内容涉及世界观相关 NPC（如艾琳、鲍里斯），但条目 keys 仅收录地名或事件，未收录该角色名字，导致检索器根据在场名单匹配时直接跳过。
3. **规则分类策略粗糙**：
   - `creative_constraints`（创作约束）在快照中带有 `sticky: 1`，但正文未加 `【世界观/世界规则】` 前缀且未设 `sourceType: 'rule'`，被误判为 `lore`。高 Token 压力下会被误当成普通背景剪除。

---

## 6. ContextTrace 增强与隐私保障

已在 `lib/application/narrative/narrative_context.dart` 中完成最小化、高信息密度的 ContextTrace 增强：

- 新增 `WorldRetrievalAuditItem` 结构，在 `WorldRuntimeContext.retrievalAudit` 中保留所有候选条目的判定记录：
  - `entry_id`: 候选条目 ID
  - `source_type`: 来源类型
  - `classified_kind`: 运行时判定的分类（constraint / fact / lore）
  - `matched_keys`: 命中关键词数量
  - `location_matched`: 是否触发地点直接命中
  - `sticky`: 是否为粘性条目
  - `score`: 综合排序得分
  - `estimated_tokens`: 预估消耗 Token
  - `included`: 最终是否入选 Prompt
  - `filter_reason`: 过滤原因（`duplicate` / `irrelevant` / `token_budget`）
- **隐私保护原则**：诊断数据（`toDiagnostics()`）中**严禁包含 WorldEntry 的大段正文**，仅记录 ID、数值和决策标识，避免敏感数据或超长文本污染日志（已通过专用隐私回归测试验证）。

---

## 7. 架构裁定：是否需要引入向量检索？

### 7.1 核心结论：**C. 值得引入 Hybrid Retrieval（混合检索）**

基于量化测试数据，单纯依赖增强 metadata / aliases 无法彻底解决叙事召回瓶颈：

1. **数据支撑**：
   - 当前纯关键词方案的总召回率仅为 **61.5%**；
   - 在同义表达、间接描述、口语化变体场景下，召回率骤降至 **0.0%**；
   - 即使通过完善数据建模（补充别名映射、修复角色 key、修正创作约束分类），召回率最高只能恢复到约 **73%**，仍有超过 1/4 的自然语义改写和指代被永久遗漏。
2. **叙事连续性危害**：
   - 当玩家通过自然口语询问已知传闻或地点（如“北方那个学法术最厉害的城市”），AI 若因检索不到而声称“世界上没有这种地方”或捏造全新设定，将严重破坏冒险的沉浸感与长期记忆一致性。

### 7.2 严格边界约束

若未来启动 Hybrid Retrieval 实施，必须遵循以下不可动摇的边界：

1. **优先接入 World Context，暂不接 Runtime HEAD**：
   - **理由**：Runtime HEAD 属于分支本地、强时序一致性的确定性实体状态（如角色存活状态、当前手持物品），必须由 SceneState 与 Entity Delta 绝对主导，禁止被向量模糊匹配干扰；
   - **适用面**：向量检索只针对静态/冻结的世界观知识库（`WorldEntry` 快照条目）。
2. **向量只能作为召回源（Recall Candidate Source），不能成为事实权威**：
   - 向量相似度仅用于提供“候选条目扩展”；
   - 排序分中，世界硬规则（`constraint` = 1000）与高阶事实（`fact` = 500）的权威层级依然不可动摇；
   - 任何向量召回的内容必须经过既有的 Token Budget 裁剪管道，绝不得绕过 PromptCompiler 的安全性原则。

### 7.3 推荐 Hybrid 架构接入方案

```
[玩家输入 query]
       │
       ├── 通道 A：Lexical Match (当前实现)
       │      └── 精确 keys contains + location + characterNames
       │
       ├── 通道 B：Semantic Match (未来引入的轻量向量召回)
       │      └── 对 query 生成向量，在冻结的世界观条目向量库中取 Top-K (K <= 5)
       │
       └── 候选集合并 (Candidate Union & RRF / Score Boost)
              │
              ├── 命中通道 A：给予现有 matchedKeys 基础加分
              ├── 命中通道 B：赋予语义关联加分 (0 ~ 100 分)
              ├── 规则硬约束：保持 1000 分置顶
              │
              └── 排序与统一 Token Budget 裁剪
```

---

## 8. 回归保护与验证

- **回归测试覆盖**：
  - 核心叙事运行时测试（`test/unit/narrative_runtime_test.dart`）：全部通过
  - 300 轮长剧情压力与分支隔离测试（`test/unit/context_long_story_stress_test.dart`）：全部通过
  - 检索质量评测套件（`test/unit/world_context_retrieval_benchmark_test.dart`）：14 项用例全部通过
- **受保护系统**：
  - Runtime HEAD 投影机制未受任何破坏；
  - SceneState 演化流程与冲突判定未受破坏；
  - 最近历史消息截断与 Token 预算分配未受破坏；
  - 现有 SQLite 数据结构与版本完全向后兼容。

---

## 9. 剩余风险与后续建议

1. **创作约束分类优化建议（P1.5）**：
   - 建议在 `WorldContextBuilder._classify` 中补充对 `content.contains('【世界观/创作约束】')` 的识别，或在快照生成时为其赋予 `sourceType: 'rule'`，防止其在极端小预算下被当成普通背景剪除。
2. **地点层级双向匹配建议（P1.5）**：
   - 建议增加 `location.contains(entry_place)` 与 `entry.content.contains(location)` 的双向检查，平滑子地点与母城区的层级断裂。
3. **向量引擎选型建议（P2）**：
   - 引入向量检索时，必须选用本地或平台原生的轻量嵌入（如本地 SQLite 扩展或轻量纯 Dart/FFI 方案），不得增加外部模型网络依赖。
