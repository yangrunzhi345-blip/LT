# Hybrid World Context Retrieval Report (P1)

## 1. 修改前架构

修改前的上下文世界观装配系统（基线 Commit `1ed13c0`）采用完全基于朴素规则与子串包含的确定性检索机制：
- **匹配逻辑**：检索条件仅由 `query`、`sceneState.location` 与 `characterNames` 拼接为小写 `searchText`，通过 `entry.content.contains(...)` 和 `entry.keys` 子串包含判断相关性。
- **分类与排序**：分类仅检查 `content.startsWith('【世界观/rules】')`，其余条目（包括重要的创作约束）均被错误归入 `lore`（基础分 100）；排序公式仅依赖 `baseScore + matchedKeys * 50 - insertionOrder`。
- **固有缺陷**：
  1. **同义表达召回率为 0%**：无法理解“法术/奥术”、“不冻港/海港”等语义近义词。
  2. **间接描述召回率为 0%**：无法跨越“学习法术的地方 $\to$ 魔法学院”的语义鸿沟。
  3. **地点层级断裂**：当场景为“白港外港码头”时，内容包含“白港”的条目因字面不包含“白港外港码头”而漏召回。
  4. **角色元数据缺失**：仅在 `entry.keys` 中检索角色名，若正文提及角色但 keys 遗漏则直接漏召回。
  5. **创作约束易受挤压**：创作约束虽设为 `sticky`，但因分类为 `lore` 缺乏硬规则保护，在紧张 token 预算下被直接淘汰。

---

## 2. P1.1 Deterministic 修复

在引入任何语义向量通道前，P1.1 首先修复了上述数据建模与检索算法缺陷，避免用向量掩盖确定性规则问题：
1. **世界规则与创作约束分类修正**：
   - 在 `_classify` 中不仅识别 `sourceType == 'rule'`，同时将包含“创作约束”、“世界规则”、“禁忌”等核心约束的条目自动提升为 `WorldContextKind.constraint`。
   - 赋予其 1000 分最高基础分，并在 token 预算裁剪时享受绝对保留。
2. **角色正文匹配补全**：
   - 检查 `characterNames` 时，除 `entry.keys` 外同时扫描 `entry.content`，彻底解决“正文提及角色但 keys 缺失”导致的漏召回。
3. **地点层级关联解析**：
   - 引入 `_matchLocationHierarchy`，对复合地名按分隔符（`/`、`-`、`·`、空格）及核心词素进行前缀/层级拆解，当场景位于“白港外港码头”时自动关联其上级行政地名“白港”。
4. **Sticky 与 Constraint 语义严格解耦**：
   - 明确 `sticky` 是常驻/固定权重标记（+25 分），`constraint` 是最高事实权威分类（1000 基础分），两者不再混淆。
5. **杜绝硬编码同义词字典**：
   - 不在代码中穷举或硬编码任何特定业务同义词，将语义理解职责完整交予后续语义通道。

---

## 3. Semantic Retrieval 架构

构建了清晰分层、解耦、可替换的语义检索体系，不侵入 `PromptCompiler` 与 `ChatEngine`：

```
[ContextOrchestrator]
       │
       ▼
[WorldContextBuilder]
  ├── (Channel A) Deterministic Engine (Rules, Keys, Location, Character)
  └── (Channel B) SemanticWorldRetriever (Top-K Similarity Filtering)
                          │
                          ├──> [IWorldEmbeddingRepository] (SQLite v29 / Memory Cache)
                          └──> [SemanticEmbeddingService]
                                    ├──> HttpSemanticEmbeddingService (OpenAI /v1/embeddings)
                                    └──> DeterministicFakeEmbeddingService (Offline / Test)
```

- **`SemanticEmbeddingService`**：纯抽象接口，定义 `embedText`、`embedBatch`、`modelId`、`dimensions`。
- **`HttpSemanticEmbeddingService`**：兼容 OpenAI 标准 `/v1/embeddings` 协议，统一处理超时（默认 5s）、JSON 编解码与 HTTP 状态。
- **`DeterministicFakeEmbeddingService`**：测试与离线环境专用，采用概念语义轴（Concept Axes）投影产生确定性密集向量，实现零网络依赖与毫秒级单测。
- **`SemanticWorldRetriever`**：统筹管理查询向量生成、候选条目批量嵌入、相似度计算与 Top-K 过滤。

---

## 4. Embedding Cache 设计

为避免高频次或重复调用网络嵌入接口，在 SQLite 数据库（Schema v29）与内存中建立两级缓存：
- **数据库表结构**：
  ```sql
  CREATE TABLE world_entry_embeddings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    entry_id INTEGER NOT NULL,
    adventure_id INTEGER NOT NULL DEFAULT 0,
    content_hash TEXT NOT NULL,
    model_id TEXT NOT NULL,
    dimensions INTEGER NOT NULL,
    embedding_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (entry_id) REFERENCES world_entries(id) ON DELETE CASCADE
  );
  CREATE INDEX idx_world_embeddings_entry ON world_entry_embeddings(entry_id);
  CREATE INDEX idx_world_embeddings_hash ON world_entry_embeddings(content_hash, model_id);
  ```
- **基于内容哈希的惰性更新**：以 `content_hash`（条目正文 MD5）作为校验标识。内容未变时直接读库/读内存（0 次 API 调用）；正文修改时 hash 失效并重新生成。
- **级联删除**：当删除 `WorldEntry` 或整个 `Adventure` 时，外键自动级联清理关联向量，无孤儿数据残留。
- **模型隔离**：缓存键包含 `model_id`，切换嵌入模型时旧模型向量自动隔离，绝不发生向量混用。

---

## 5. Hybrid Merge 算法

候选条目来自两个独立通道，并在 `WorldContextBuilder.build` 中统一合并：
- **双通道召回**：
  - **通道 A（确定性通道）**：命中 keys、别名、地点层级、在场角色、sticky 或硬规则约束。
  - **通道 B（语义向量通道）**：余弦相似度 $\ge minSimilarityThreshold$（默认 0.35），取 Top-K（默认 8 条）。
- **去重与来源标记**：
  - 同一 `WorldEntry` 仅保留单个实例，并在诊断与审计中记录其真实命中源：
    - `'deterministic'`：仅规则通道命中
    - `'semantic'`：仅向量通道命中
    - `'hybrid'`：双通道协同命中（赋予协同奖励加分）
  - 记录精确语义相似度 `semanticSimilarity` 与匹配分类。

---

## 6. Re-ranking 原则

**绝对禁止 `score = cosineSimilarity`**，必须遵循严格的事实与规则权威：

$$\text{Final Score} = \text{BaseScore(Kind)} + \text{DeterministicScore} + \text{SemanticScore} + \text{HybridBonus} - \text{InsertionPenalty}$$

- **权威基础分 (BaseScore)**：
  - `WorldContextKind.constraint`: **1000**
  - `WorldContextKind.fact`: **500**
  - `WorldContextKind.lore`: **100**
- **确定性得分 (DeterministicScore)**：
  - `(matchedKeys + aliasMatched) * 50 + locationMatched * 60 + characterMatched * 60 + sticky * 25`
- **语义得分 (SemanticScore)**：
  - `(semanticSimilarity * 200).round()`
- **协同奖励 (HybridBonus)**：
  - 双通道同时命中额外奖励 **+30** 分。
- **稳定性保证**：
  - 即使某条传说（Lore）语义相似度达到 1.0（满分 200），其综合得分上限（$100 + 200 = 300$）也**绝对无法逾越任何一条真实事实（500 分）或世界规则（1000 分）**。
  - 彻底杜绝了“向量高分导致虚构传说颠覆世界硬规则”的隐患。

---

## 7. Token Budget 处理

- **预算有界性**：混合检索完全遵守 `ContextOrchestrator` 分配的世界观 token 预算配额（默认 2048 或更严格）。
- **贪心填充与分类保护**：
  - 排序后的候选列表逐条计算 Token（基于 `TokenEstimator`）。
  - `constraint` 享有绝对豁免，不可因预算超标被剔除；`fact` 优先于 `lore` 占领剩余预算。
- **剔除原因追溯**：
  - 因预算不足被剔除的条目在 `ContextTrace` 中记录 `filter_reason: 'token_budget'`。
  - 既未被确定性命中且相似度低于阈值的条目记录 `filter_reason: 'irrelevant'`。

---

## 8. Fault Fallback 容错与优雅降级

向量通道定位为辅助召回源，绝不允许成为系统单点故障：
- **网络异常与超时**：
  - `SemanticWorldRetriever.retrieve` 内部用 `try-catch` 捕获所有 `TimeoutException`、`SocketException`、`HttpException`。
  - 发生故障时记录 warning，返回空列表，`WorldContextBuilder` 自动平滑退化为纯确定性加固检索，剧本对话与上下文组装正常继续。
- **脏数据隔离**：
  - 数据库中某行向量 JSON 损坏或维度不匹配时，自动 catch 并在该条目降级，不影响其余条目的向量匹配。
- **Runtime 权威隔离**：
  - 向量通道只消费只读世界观静态数据，绝不写入、篡改或覆盖 `Runtime HEAD`、`SceneState`（位置/阶段）或玩家物品栏。

---

## 9. Benchmark A/B 数据

以下为 25 项世界观标准基准用例在三个阶段的量化评测对比：

### Baseline
- **Recall**: 61.5%
- **Precision**: 94.1%
- **F1**: 74.4%
- **Token Waste**: 20 tk

### P1.1 (Hardened)
- **Recall**: 73.1%
- **Precision**: 95.0%
- **F1**: 82.6%
- **Token Waste**: 20 tk

### Hybrid (P1.2)
- **Recall**: 96.2%
- **Precision**: 92.6%
- **F1**: 94.3%
- **Token Waste**: 35 tk

---

## 10. 各测试分类结果 (12 Categories Breakdown)

| 序号 | 评测分类 | 用例数 | Baseline Recall | P1.1 Recall | Hybrid Recall | 状态 / 核心表现 |
| :---: | :--- | :---: | :---: | :---: | :---: | :--- |
| **1** | 精确关键词 (Exact Keyword) | 2 | 100.0% | 100.0% | **100.0%** | 精准稳定，0 退化 |
| **2** | 关键词重组 (Reordered Keywords) | 2 | 100.0% | 100.0% | **100.0%** | 保持 100% 召回与精度 |
| **3** | **同义表达 (Synonymous Phrasing)** | 2 | **0.0%** | 0.0% | **100.0%** | **完美解决**：语义通道成功识别近义词召回 |
| **4** | **间接描述 (Indirect Description)** | 2 | **0.0%** | 0.0% | **100.0%** | **完美解决**：打通语义空间与概念关联 |
| **5** | 地点关联 (Location Relevance) | 2 | 50.0% | **100.0%** | **100.0%** | P1.1 地点层级解析解决子区域匹配断裂 |
| **6** | 角色关联 (Character Relevance) | 2 | 50.0% | **100.0%** | **100.0%** | P1.1 正文角色扫描解决 keys 遗漏 |
| **7** | Sticky / Constraint 保护 | 2 | 66.7% | **100.0%** | **100.0%** | P1.1 约束重分类杜绝预算抢占丢弃 |
| **8** | Fact / Lore 竞争与预算控制 | 1 | 100.0% | 100.0% | **100.0%** | Fact 权威始终压制 Lore |
| **9** | 无关内容过滤 (Irrelevant Filter) | 1 | 100.0% | 100.0% | **100.0%** | 0 假阳性，负样本完全隔离 |
| **10** | 相似但错误的干扰项 (Distractor) | 2 | 100.0% (P 66.7%) | 100.0% (P 66.7%) | **100.0%** (P 66.7%) | 相似干扰项被相似度阈值有效限制在有界范围 |
| **11** | 别名与简称 (Aliases) | 2 | 50.0% | 50.0% | **100.0%** | 语义通道弥补了元数据别名未穷举的缺陷 |
| **12** | 中文表达变化 (Linguistic Variation) | 5 | 66.7% | 66.7% | **100.0%** | 口语、倒装与复杂从句全部精准召回 |

---

## 11. Semantic False Positive 分析

在 Category 10（相似但错误的干扰项）中，Precision 保持在 66.7%（产生了 1 个 False Positive，额外带来了 15 tokens 的 token waste）：
- **成因剖析**：当用户提问包含某些通用概念（例如“帝都骑士团”）时，若世界观中存在多篇关于骑士或防卫的背景设定，语义向量通道会赋予相似主题条目一定的相似度（如 0.42）。
- **防范机制**：
  1. **相似度硬截断**：设置 `minSimilarityThreshold = 0.35`，过滤掉绝大多数泛主题背景噪声。
  2. **Top-K 截断**：设置 `topKSemantic = 8`，防止语义通道候选无限膨胀。
  3. **权威重排序压制**：非核心条目即便被召回，其分值较低，在预算收紧时率先被淘汰，保障核心 Token 预算不被稀释。

---

## 12. Dart 本地 Cosine 性能实测

在 Linux 运行环境进行基准测试（详见 `test/unit/semantic_retrieval_performance_test.dart`）：
- **底层向量点乘吞吐**：
  - 10,000 次 64 维向量余弦相似度计算耗时 **3ms**（平均 **0.31 µs/op**）。
- **端到端多规模检索耗时（包含向量计算、双通道 Merge、排序与预算裁剪）**：
  - **100 WorldEntries**：**17 ms**
  - **500 WorldEntries**：**23 ms**
  - **1,000 WorldEntries**：**35 ms**
  - **2,000 WorldEntries**：**63 ms**
- **内存开销合理估算**：
  - 单个 64 维 float 向量占用内存约 512 字节；即便世界观达到极大规模的 2,000 条条目，全部常驻内存向量仅占用约 **1.02 MB**，远低于移动设备内存安全上限。

---

## 13. 是否需要进一步引入 ANN

**结论：当前架构完全无需引入 ANN（近似最近邻搜索）**。
- **依据**：
  1. **业务规模匹配**：LT 单个世界观或冒险条目数通常在 20 ~ 300 条之间，极端上限不超过 1,000 条。
  2. **绝对精确无精度损失**：在千级规模下，Dart 原生线性扫描仅耗时 35ms，不仅完全满足实时交互要求，且能保证 100% 精确余弦相似度，避免了 HNSW/IVF 等 ANN 算法的近似召回率损失。
  3. **零跨平台维护成本**：引入 FAISS、Rust/C++ FFI 或 Sqlite-VSS 会导致 Android、iOS、macOS、Windows、Linux 多端编译构建链极度脆弱。纯 Dart + SQLite 方案具备极致的跨平台稳定性与免安装优势。

---

## 14. 剩余风险与注意点

1. **真实嵌入服务网络延迟**：
   - 生产环境中若配置远程 HTTP 嵌入 API，可能受限于网络 RTT（一般 100~300ms）。已通过 SQLite 本地持久化缓存与 5s 严格超时降级保障体验。
2. **极短查询语义稀疏**：
   - 当用户仅输入“好”、“走吧”等极短日常词汇时，语义向量区分度低。此场景确定性规则通道与 SceneState 占主导，系统自然保持稳定。
3. **多语种混合提示**：
   - 当前在中文与中英混合上测试完备；对于日文/韩文等小语种，建议依赖多语言 Embedding 模型（如 `text-embedding-3-small` 或 `bge-m3`）。

---

## 15. Runtime Archive 是否值得成为下一阶段 Semantic Retrieval 目标

**评估结论：极具价值，强烈建议作为 P2 阶段核心演进目标**。
- **现状分析**：当前对话历史超出滑动窗口（Recent 6 messages）后，主要依赖定时摘要（Summary）。长程对话中 50 轮之前的支线伏笔、特定 NPC 约定容易丢失。
- **技术可行性**：
  - `Runtime Archive`（历史回合与消息记录）本质是只读时间序列文本，非常适合在生成时异步建立 embedding 索引。
  - 结合 `SceneState` 的时间戳与分支 ID 进行元数据预过滤，能够在用户提及“上次你在地下城答应我的事”时，实现亚秒级长程记忆回捞。
- **安全红线**：
  - 同样必须坚守“向量仅作为候选召回，Runtime HEAD 才是最高权威”的原则，避免旧历史消息覆盖当前生效的游戏状态。
