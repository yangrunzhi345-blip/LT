# 001 — Rust 核心迁移审计报告

## 基线

- 仓库：`yangrunzhi345-blip/LT`
- HEAD：`95705eb99ebc36996b76e0607ec9966f259c2fde`（执行时 `main` 最新）
- `flutter analyze`：No issues found
- `flutter test`：425 全部通过
- 工具链：Flutter 3.44.8 / Dart 3.12.2 / cargo 1.94.1 / rustc 1.94.1
- 现有 Rust / FFI 基础设施：**无**（无 `Cargo.toml`、无 `rust/`、无 flutter_rust_bridge）

## 结论（先行）

**严格门禁下，本轮不迁移任何模块到 Rust。全部目标模块继续保留 Dart。**

判定依据见 `002-rust-benchmark-baseline.md` 的实测数据。核心原因可归纳为三点：

1. **所有目标模块都不是热路径**：均为“每回合一次”的调用，不在任何循环内；即使 Rust 内部快 3–5×，端到端收益也以毫秒甚至微秒计，对用户体验为零。
2. **FFI 序列化成本吞噬收益**：`WorldEntry` / `SupportingCharacter` / `CustomAttributeItem` / `RuntimeEntityState` 均为带嵌套结构的 Dart 对象，跨 FFI 边界必须 JSON 或自定义二进制序列化；该成本在大多数场景 ≥ 计算本身。
3. **生产数据规模远小于 benchmark 规格**：50K World Entries、10K Runtime States 是合成负载；真实世界观通常几十到几百条，运行时实体 ≤ 8 个。

唯一出现“可观耗时”的 `NarrativeLengthGuard`，其根因是 **O(n²) 算法**（正则 `countChinese` 在 `convergeToMaximum` / `_trimToSentenceBoundary` 中被反复调用），而非“Dart 语言慢”。正确修复是算法层面（增量计数 / 单次扫描），在 Dart 内即可完成，不构成 Rust 迁移理由。

## 目标模块清单与 go/no-go

| 模块 | 文件 | 调用频率 | 生产数据规模 | Dart 实测（生产量级） | 决策 |
|---|---|---|---|---|---|
| `TokenEstimator` | `lib/utils/token_estimator.dart` | ~15–30 次/回合 | KB 级字符串 | 100 条 0.1ms / 50K 条 2ms | **不迁移** |
| `WorldContextBuilder` | `lib/application/narrative/narrative_context.dart:220` | 1 次/回合 | <200 条 | ≤1K 条 5.4ms | **不迁移** |
| `RuntimeMemoryProjector` | 同文件 `:172` | 1 次/回合 | ≤8 entities | ≤100 条 0.022ms | **不迁移** |
| `RuntimeStateValidator` | `lib/services/runtime_state_validator.dart` | 1 次/回合 | ≤32 proposals | ≤100 条 0.031ms | **不迁移** |
| `CustomStatusMerger` | `lib/services/custom_status_merger.dart` | 1 次/回合 | 少量属性 | ≤100 属性 0.043ms | **不迁移** |
| `NarrativeLengthGuard` | `lib/engines/chat_engine_internals/response_length_guard.dart` | 数次/回合 | ≤10K 字（L5 上限） | 10K 字 46ms（一次性溢出防御） | **不迁移**（记算法风险） |

## 为什么都不达标（端到端视角）

任务规定的判定标准是**端到端 Dart↔Rust 调用后的真实提升**，且 `<1.5× 默认不迁移`。对上述模块逐一分析：

### TokenEstimator —— 批量估算也不值得

- 纯算术，理论上最适合 Rust。
- 但 Dart 基线已经极快：50K 条 ~150 字字符串 ≈ 2ms。
- 若走 FFI 批量估算，Dart 侧必须先把 50K 个 `String` 拼接/序列化为一块可传给 Rust 的缓冲区（UTF-8 编码 + 拷贝），该成本量级已接近甚至超过 2ms。
- 生产实际是“每回合几个 KB 文本”，单次估算在微秒级。Rust 即便内部快 5×，端到端也是负数或持平。

### WorldContextBuilder —— 唯一“有量”的模块，但规模不成立

- 50K 条 243ms 是本次唯一可观的绝对耗时。
- 但这是合成负载。真实世界观条目几十到几百，1K 条仅 5.4ms，且每回合只跑一次（人机对话节奏下不可感知）。
- 迁移需序列化全部 `WorldEntry`（含 `keys` 列表、枚举、`enabled` 位），Rust 再重建 `_classify`（中文前缀）、`_normalize`（正则）、`matchedKeys`、评分、排序、预算选择。序列化 + 解析成本会吃掉大部分省下的计算时间。

### RuntimeMemoryProjector / RuntimeStateValidator / CustomStatusMerger —— 微秒级

- 三者生产量级耗时均 <0.05ms，且每回合一次。
- 迁移意味着把 `CustomAttributeItem`（依赖 `Equatable` + Flutter `material`）、`SupportingCharacter`（嵌套属性列表）等对象序列化过边界，成本远超收益。

### NarrativeLengthGuard —— 唯一“疑似热点”，但根因是算法

- 100K 字 3.7s / 10K 字 46ms，源于 `countChinese`（正则 `allMatches`）在 `convergeToMaximum` 段落循环、`_trimToSentenceBoundary` 句子循环中被重复调用，整体呈平方复杂度。
- 生产上限 `hardMaximum ≤ minChineseChars*3`，绝对上限 ~10K 字（L5）；典型 L2–L3 为 1–3K 字（1–10ms）。100K 字在真实系统不可能出现。
- 正确解法是算法优化（增量计数 / 边界单次扫描），Dart 内即可完成，且属于“顺手优化”范畴，不在本任务（Rust 迁移）范围内，仅记录风险，不擅自修改。

## 明确禁止迁移（按任务要求，未发现 CPU 热点，维持 Dart）

Flutter UI、Riverpod、Controller、普通 Application UseCase、Settings、LLMService、HTTP/Streaming、DeepSeek/OpenAI 参数策略、`LlmTaskPolicy`、`ModelCapabilities`、typed LLM transport、普通 SQLite CRUD、Repository orchestration、TTS、网络重试、Adventure option repair 网络逻辑。

## FFI 方案（仅作未来参考，本轮不启用）

若未来出现真正需要 Rust 的场景，已与用户确认采用 **flutter_rust_bridge（FRB）**：

- typed / null-safe / 明确 error type 天然满足；
- 跨 Linux x86_64 / Windows x86_64 / Android arm64 的 build 与 codegen 支持成熟；
- 统一通过单一 `RustCoreGateway` 访问，禁止 `Screen/Widget/Provider → Rust` 直连。

## 风险与行为一致性（若未来迁移需逐字保持）

已识别的高危语义差异点（任何 Rust 重写必须逐一 lock 成 differential test）：

1. `countChinese` 存在**两套实现**：`chat_engine.dart:307` 计 `0x4E00–0x9FFF` **加** `0x3400–0x4DBF`；`response_length_guard.dart:90` 只计前者。二者不可混用。
2. `WorldContextBuilder._normalize` 的正则：`\s+` 与 `[，。！？、；：,.!?;:\-—_\[\]【】]` 的 Unicode 范围必须逐字节一致。
3. `_classify` 的中文前缀判断（`【世界观/世界规则】`、`【世界观/当前世界状态】`、`【世界观/locations】`、`【世界观/factions】`）。
4. `CustomStatusMerger._namesMatch` 的“主角/玩家/自身/我”与“同伴/配角/队友”启发式、`·` 姓拆分。
5. `_applySet` 的“同值措辞不覆盖”语义、`_applyChange` 的 `delta` 仅数值、`clamp(0, max)`。
6. `RuntimeStateValidator` 的重复 path 抛错、derived 需 reason、各 path 的类型约束。
7. `RuntimeMemoryProjector` 的 `maximumEntities=8` / `maximumTokens=600` 截断与 `filteredEntityCount` 语义。

## 附录：commit 与产物

- `benchmark/core_benchmark.dart`：Dart 基线 benchmark harness（`flutter test benchmark/core_benchmark.dart` 运行）。
- 本文件 + `002-rust-benchmark-baseline.md`：审计与基线文档。
