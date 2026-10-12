# 角色卡生成弹性、分级预算与 DeepSeek 适配重构 — 实施规格

Status: APPROVED FOR EXECUTION (Integrated Single-Agent Full-Cycle Mode)
Baseline: `e5a86dc` (v1.2.07-1-ge5a86dc, main, 工作区干净)
Date: 2026-10-11

## 1. 已确认根因（当前代码事实）

### R1 生成累计预算无弹性（核心）
- 权威预算来源是 `resource_blueprints.target_capacity`（= 用户目标 T）。
- `PartGenerationTaskRepositoryImpl.remainingBudget`
  （`lib/application/resources/resource_generation_task_repository.dart:419-444`）
  与 `commitPartContent` 的提交内校验（同文件 :523-547）均以 **T 为累计硬上限**：
  `otherCharacters + content.length > T` 即拒绝。
- 早期 Part 超预计（如 4×2100 vs 目标 8000）时，后期 Part 的
  `remaining <= 0`，在 coordinator（`part_generation_coordinator.dart:998-1004`）
  直接抛 `PartGenerationValidationException`，重试预算耗尽后整个 run 失败。
  这就是“后期 Part 容量耗尽 / 高字数角色卡无法完成生成”的根因。
- 单段传输上限 `maximumAcceptedCharacters = remaining.clamp(0, 3000)`
  （`resource_generation_protocol.dart:210-215`），本身正确，保留。

### R2 分级与压缩链路（审计结论）
- 容量分级权威：`ResourceCapacityPolicy.statusFor`（`resource_limits.dart:169-180`）。
  exactly nominal → normal；exactly absolute → elastic；> absolute → overflow。
- 装配就绪只对 **overflow** 强制压缩（`assembly_readiness_coordinator.dart:247`）；
  normal 与 elastic 直接装配。运行时上下文预算由 `ContextBudget.resolve`
  （模型窗口推导）+ `WeightedContextPlanner` per-source 上限承担，与压缩无关。
- `resourceContextTokenBudget = 6000`：**死常量**，生产代码零引用。
- `compressionTriggerContextTokens = 8000`：仅作为 `CompressionThresholds.contextTokenLimit`
  默认值，而 `evaluateContext` 无生产调用方。二者当前不构成任何触发闭环，
  不存在“6000 预算 vs 8000 触发”导致的问题。实际生产触发是容量分级
  （`CompressionTriggers.evaluateResource`：overflow 强制 / elastic 机会性，
  后者仅由 `CompressionBackgroundWorker.onEditorLeave` 用于后台候选，不阻塞装配）。
- 压缩生命周期已有界：lease 5 分钟、`recoverStaleJobs` 每 drain 执行、
  failed 不自动重排、唯一重试入口显式（`retryJob` / `retryFailedJobs` /
  `retryPreparation`）。原始正文永不覆盖（candidate + 显式 publish）。
- overflow 资源若所有 Part > `maxCompressionInputCharacters`(12000) 或均为
  结构化 JSON，`enqueueForResource(partOnly:true)` 返回空 → `compressionNoTargets`
  → failed（fail-closed，可显式重试或用户编辑）。这是有意的保护（commit 38769c9），
  保留。AI 生成因 C ≤ A 不可能产生 overflow，因此该死端只影响历史/导入数据。

### R3 计量口径
- 容量权威计量：解码后正文的 `String.length`（Dart UTF-16 code units），
  排除 JSON 包装/NDJSON 协议字段（已由 accumulator 保证）；
  `ResourceIntegrityValidator._cardBodyLength` 对 background==description 镜像去重。
  口径一致，无重复计数。保持不变。
- 模型 token 与字符的关系：DeepSeek 官方 1 汉字 ≈ 0.6 token；
  单段 3000 字 × 0.6 ≈ 1800 token ≪ maxTokens 4096，单段不会截断。保留 3000。

### R4 提示词
- 现有系统提示第 5 条把 T 描述为“目标”但语气偏“配额”；instruction 中
  “整份资源实际剩余预算/正文接受上限”行保留（值改为基于 C）。
- DeepSeek NDJSON 兼容性：`json_object` 模式与多行 NDJSON 不等价，现有协议
  不使用 `preferJsonOutput`（`LlmTask.resourcePartGeneration` 为 false），正确，不改协议。

### R5 前端
- 滑块/输入归一化（1000–nominal、步进 500）与生成目标一致，保留。
- 缺少弹性上界与偏差展示；“大致目标字数”文案未说明软目标语义。

## 2. DeepSeek 能力调查（官方事实，2026-10-11 核实）

来源：api-docs.deepseek.com（list-models / create-chat-completion / pricing / thinking_mode / token_usage）。

| 项目 | 官方事实 |
|---|---|
| `deepseek-flash` | = DeepSeek-V4.1-Flash；legacy `deepseek-v4-flash` 仍被接受并路由到 V4.1-Flash |
| `deepseek-v4-pro` | = DeepSeek-V4-Pro-0813 |
| 上下文 | 1M；最大输出 384K（`max_tokens` 合法域 1–393216） |
| `max_tokens` 默认 | 非思考 8K；思考 64K；思考+`max` effort 128K |
| 思考模式 | 默认开启、effort 默认 high；`reasoning_effort` ∈ none/low/high/max（minimal→low、medium→high、xhigh→high） |
| 思考输出 | `reasoning_content` 与 `content` 平级返回；`usage.completion_tokens_details.reasoning_tokens` 单列 |
| `finish_reason` | stop / length / content_filter / tool_calls / insufficient_system_resource / aborted |
| `json_object` | 必须在提示中要求 JSON，否则可能无限空白；`finish_reason=length` 时内容可能截断 |
| token 计量 | 1 汉字 ≈ 0.6 token、1 英文字符 ≈ 0.3 token；以 API `usage` 为准 |

适配结论：
- Part 生成 `maxTokens=4096` 固定（`llm_task_policy.dart:108-115` + gateway 默认）
  对单段 ≤3000 字（≈1800 token）充足，不产生截断；不改。
- `resourcePartGeneration` thinking=followUserSetting：尊重用户开关，不擅自改变。
- NDJSON 协议不用 `json_object`，不受其截断语义影响。
- 未验证事项：真实 DeepSeek API 的 NDJSON 遵循率、长 Part 长度遵循分布；
  本任务不发送付费请求，Mock 结论不宣称真实 API 验收。

## 3. 设计

### 3.1 统一预算策略（新领域纯函数，置于 resource_limits.dart）

```
T = 用户生成目标（≤ nominal）
A = ResourceLimits.policyFor(type).absoluteCharacters
E = 0.20（generationElasticRatio）
C = GenerationBudgetPolicy.cumulativeCeiling(target: T, absolute: A)
  = T <= 0 ? 0 : min(floor(T * (1 + E)), A)
```

- T 是软目标；C 是生成任务累计硬边界；A 是资源容量绝对边界。
- 容量分级不变：仍以 nominal/absolute 判定 normal/elastic/overflow。
  生成目标偏差（actual vs T）只做 UI 展示，不影响容量分级。

### 3.2 接入点（唯一公式，两处消费）

- `remainingBudget`：C − Σ(其他活跃 Part 正文长度)（排除当前 Part 旧正文，逻辑不变）。
- `commitPartContent` 事务内：`otherCharacters + response.content.length <= C`
  否则 `PartGenerationValidationException('generation_budget')`（不变，阈值改为 C）。
- 类型来源：`resource_blueprints.resource_type`（NOT NULL，权威）；
  未知类型 fail-closed（`ResourceContractException` 传播）。
- `maximumAcceptedCharacters` 与 validator 不变（单段 3000 上限保留）。

### 3.3 提示词（Phase 6）
- 系统提示第 5 条改为：约 N 字为**软目标**，质量与设定一致性优先，按叙事自然展开、
  无需刻意填满；硬边界是客户端校验的接受上限（maximumAcceptedCharacters）。
- 不要求模型统计累计字数；cursor 权威、结构禁令、协议行全部保留。

### 3.4 前端（Phase 7）
- AI 创建页长度区新增一行：允许生成上界 = C（随目标/类型联动）。
- `resourceGenerationLengthDescription` 五语更新为软目标 + 最多 20% 自然扩写语义。
- 滑块/输入归一化不变（仍 ≤ nominal）。

### 3.5 压缩（Phase 5）
- 不改触发语义（容量驱动即上下文需求的保守代理；运行时另有窗口推导预算）。
- 仅更新 `resource_limits.dart` 中 6000/8000 常量注释，记录其当前角色与审计结论，
  防止未来误用。无行为变更。

## 4. 修改文件

| 文件 | 修改 |
|---|---|
| `lib/domain/resources/resource_limits.dart` | 新增 `GenerationBudgetPolicy`；更新死常量注释 |
| `lib/application/resources/resource_generation_task_repository.dart` | `remainingBudget`/`commitPartContent` 以 C 为累计上限（读 blueprint resource_type） |
| `lib/application/resources/part_generation_prompt_builder.dart` | 软目标措辞 |
| `lib/features/resource_library/presentation/screens/resource_ai_create_page.dart` | 弹性上界展示行 |
| `lib/l10n/app_en.arb` `app_zh.arb` `app_zh_Hant.arb` `app_ja.arb` `app_ko.arb` | 文案更新 + 新 key `resourceGenerationElasticCeilingLabel` |
| `test/domain/resources/generation_budget_policy_test.dart` | 新增：8.1 预算矩阵（策略级） |
| `test/application/resources/generation_aggregate_budget_sqlite_test.dart` | 更新为 C 口径；新增边界/并发/24000±1 场景 |
| `test/application/resources/part_generation_prompt_builder_test.dart` | 提示词断言更新 |

禁止范围：不改 NDJSON 协议、不改单段 3000、不改容量分级、不改压缩状态机、
不改 TTS/导航/关系系统、不动版本号、不 push。

## 5. 验收标准

- 8.1 矩阵全部通过（策略级 + SQLite 级边界）。
- 8.2 分段场景：8000 目标 4×2100=8400 可保存；并发突破 C 被拒；C±1 边界正确。
- 既有全量 `flutter test` 通过（明确更新过的预算口径测试除外）。
- `dart format` / `flutter analyze` / `git diff --check` 通过。
- 旧数据兼容：无 target_capacity（=0）时 remaining=null 行为不变；
  历史资源、revision、导入、压缩候选不受影响。
