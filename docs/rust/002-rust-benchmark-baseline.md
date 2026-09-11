# 002 — Dart 核心模块性能基线

## 方法与环境

- 环境：Linux x86_64，Flutter 3.44.8 / Dart 3.12.2（JIT，`flutter test` 运行时）
- 方法：每项先 1 次 warmup，再 7 次采样取中位数（毫秒）；内存为进程 RSS 粗估（Dart 无精确分配计数器）
- 数据：确定性合成数据（`math.Random(42)`），覆盖中英混合、关键词、状态叠加等形态
- 运行方式：`flutter test benchmark/core_benchmark.dart`

## Context 基线

### TokenEstimate（批量，N 条 ~150 字字符串）

| N | Dart ms（中位数） |
|---|-------------------|
| 100 | 0.100 |
| 1,000 | 0.138 |
| 10,000 | 0.420 |
| 50,000 | 2.008 |

### WorldContextBuilder.build（normalize+dedup+match+score+rank+budget）

| N | Dart ms（中位数） |
|---|-------------------|
| 100 | 0.997 |
| 1,000 | 5.402 |
| 10,000 | 47.424 |
| 50,000 | 242.899 |

### RuntimeMemoryProjector.project

| entities | Dart ms（中位数） |
|---|-------------------|
| 16 | 0.013 |
| 100 | 0.022 |
| 1,000 | 0.104 |
| 10,000 | 0.215 |

## Runtime 基线

### RuntimeStateValidator.accept

| proposals | Dart ms（中位数） |
|---|-------------------|
| 16 | 0.005 |
| 100 | 0.031 |
| 1,000 | 0.311 |
| 10,000 | 1.522 |

### CustomStatusMerger.applyChanges

| attributes | changes | Dart ms（中位数） |
|---|--|-------------------|
| 16 | 16 | 0.013 |
| 100 | 64 | 0.043 |
| 1,000 | 64 | 0.056 |

## NarrativeLengthGuard（countChinese + convergeToMaximum）

| 纯汉字数 | Dart ms（中位数） | 备注 |
|---|-------------------|------|
| 1,000 | 1.200 | 典型 L2 量级 |
| 10,000 | 45.947 | L5 上限（hardMaximum ≤ min*3） |
| 100,000 | 3,774.619 | 生产不可达（超出 hardMaximum 上限 10×） |

## 内存（粗估）

- 50K `WorldEntry` + 50K 字符串：RSS 增量约 **5.4 MB**（进程 RSS，噪声较大）

## 判定分析

以“端到端 Dart↔Rust 调用后的真实提升 ≥2×”为迁移门槛：

| 模块 | Dart 基线 | 生产量级 | FFI 往返成本预估 | 结论 |
|---|---|---|---|---|
| TokenEstimator 批量 | 0.1–2ms | 微秒–亚毫秒 | 序列化+拷贝 ≈ 计算本身 | 不迁移 |
| WorldContextBuilder | 1–243ms | ≤5ms/回合 | 对象序列化+解析吞噬收益 | 不迁移 |
| RuntimeMemoryProjector | 0.013–0.215ms | 0.01ms | 远超收益 | 不迁移 |
| RuntimeStateValidator | 0.005–1.5ms | 0.005ms | 远超收益 | 不迁移 |
| CustomStatusMerger | 0.013–0.056ms | 0.05ms | 远超收益 | 不迁移 |
| NarrativeLengthGuard | 1.2ms–3.7s | 1–46ms（一次性溢出防御） | 根因是 O(n²) 算法，非语言 | 不迁移（记算法风险） |

**结论：无任何模块满足 ≥2× 端到端迁移门槛。严格门禁下，全部保留 Dart。**

唯一值得关注的性能信号是 `NarrativeLengthGuard` 的平方复杂度：正则版 `countChinese` 在 `convergeToMaximum` / `_trimToSentenceBoundary` 内被重复调用。若未来需要，应在 Dart 内做增量计数/单次扫描的算法优化（属独立任务，不在本轮 Rust 迁移范围）。
