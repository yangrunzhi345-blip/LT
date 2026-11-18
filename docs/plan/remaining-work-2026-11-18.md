# LT 剩余工作实施计划

- 生成时间：2026-11-18T00:23:29+08:00
- 基线：`main @ e1b0e91`
- 状态：阶段 1–5 已完成；以下为**非阻塞的后续可完成项**，按独立工作包拆分。
- 更新（2026-11-18）：第 1 项 UI 瘦身、第 2 项 Repository 拆分、第 3 项平台凭证库、第 4 项 Anthropic 正式支持已完成；第 5 项按设计不改，第 6 项仅剩真机验收，第 7 项未授权 push。

> 本文件只描述剩余工作、实施路径与验收标准，不代表当前代码存在功能缺陷。
> 所有包均要求保持现有测试绿灯；行为变化必须先更新规格与回归测试。

---

## 1. UI 进一步瘦身：Wizard 与 Runtime Hub

> **状态：已完成（2026-11-18）。** 提交 `090bc54`、`6b9ed45`。
>
> - `adventure_wizard_screen.dart` 2091 → 782 行；角色步骤 1080 → 134 行。
> - 角色步骤面板拆为 6 个显式 props Widget（header、AI 助手、资料库选择、阵容、羁绊、保存选项），位于 `wizard/widgets/character_step/`。
> - 启动编排迁入 `features/adventure/application/use_cases/start_adventure_from_wizard.dart`，返回 `WizardStartReady` / `WizardStartBlocked` / `WizardStartNeedsStaleConfirmation`；`_handleStart` 只保留输入校验、对话框、反馈与导航。
> - Runtime Hub 1037 → 591 行，Dashboard / Entities / Timeline / Turn History 迁入 `state/runtime_hub_views.dart`。
> - 新增填充阵容的响应式回归测试（320/360/390/412/768），并修复其暴露的 4 处既有 320 px 溢出。
> - 验证：`flutter analyze --no-pub` 无问题；全量 `flutter test` 4236 passed / 7 skipped。

### 未完成内容（历史记录）

- `lib/features/adventure/presentation/wizard/screens/adventure_wizard_screen.dart` 仍约 2091 行，负责状态、加载、保存/启动编排与 `build`。
- `adventure_wizard_character_step.dart` 仍约 1080 行，是当前最大的单一 UI 面板。
- `lib/features/adventure/presentation/state/runtime_state_hub_page.dart` 仍约 1037 行，包含 Hub 状态、加载、视图路由与 Dashboard/Entities/Timeline/Turn 构建。
- `_handleStart` 仍在 UI 层串联「保存世界观/角色 → 组装 → readiness gate → 启动 Adventure」。

### 完成方案

1. **角色步骤组件化**
   - 将角色步骤拆为独立 Widget：
     - 资料库角色卡网格
     - 已选角色列表 / 主角标记 / 身份定位
     - 角色关系编辑器
     - AI 关联角色区块
   - Widget 只接收显式 props 与回调，状态仍由 `_AdventureWizardScreenState` 持有。
2. **启动编排迁出 UI**
   - 新增 application use case，例如 `StartAdventureFromWizardUseCase`：
     - 保存当前世界观/角色到资料库
     - 构建 `AdventureConfig`
     - 调用 readiness gate 与 `createAdventure`
     - 返回强类型结果 / 领域错误
   - Screen 只负责收集输入、调用 use case、展示反馈与导航。
3. **Runtime Hub 视图拆分**
   - 将 Dashboard、Entities、Timeline、Turn History 四个 view builder 拆为独立 Widget。
   - 数据加载与分页保留在 Hub 的 controller/state 中，Widget 不直接持有 repository。
4. **逐步迁移**
   - 每次只拆一个面板；保持现有 Widget Key、测试定位与导航路径不变。

### 验收标准

- `flutter analyze --no-pub` 无问题。
- Wizard / Runtime Hub 相关 Widget 测试全部通过。
- 至少验证 320×568、360×640、390×844、412×915、768×1024、1280×800。
- 无 overflow、无异常、主要按钮与导航仍可用。
- `adventure_wizard_screen.dart` 目标降到约 1000 行以内；角色步骤单文件目标降到约 500 行以内。
- `_handleStart` 不再直接执行资源保存与 Adventure 启动的业务细节。

### 风险

- Wizard 状态字段多、回调密集，拆分时容易改变交互顺序；必须逐面板迁移并跑对应 Widget 测试。
- Runtime Hub 视图与 Inspector 导航耦合，需保持既有 route 与 initial view 语义。

---

## 2. Adventure Repository 进一步拆分

> **状态：已完成（2026-11-18）。** `runtime.dart` 拆为 `runtime_head_entity` /
> `runtime_history` / `runtime_checkpoint`（Checkpoint 独立成文件以满足单文件
> ≤600 行），`scene.dart` 拆为 `scene_turn_commit` / `scene_state_presence`。
> 三个跨组共用的场景写入 helper 上移至 `_AdventureRepositoryBase`。
> 现在所有子域文件 ≤565 行；`IAdventureRepository` 接口、SQL、事务边界与
> 幂等键均未改动。定向测试 83 passed，`flutter analyze --no-pub` 无问题，
> 全量 `flutter test` 4236 passed / 7 skipped。

### 未完成内容（历史记录）

当前已拆为：

| 文件 | 约行数 |
|---|---|
| `adventure_repository_impl.dart` | 309 |
| `adventure_repository_impl.runtime.dart` | 944 |
| `adventure_repository_impl.scene.dart` | 778 |
| `adventure_repository_impl.archive.dart` | 549 |
| `adventure_repository_impl.runtime_mutation.dart` | 489 |
| `adventure_repository_impl.diagnostics.dart` | 409 |

仍有两个偏大的子域：runtime 查询/历史与 scene turn/场景状态。

### 完成方案

1. 将 `runtime.dart` 拆为：
   - `runtime_head_entity`：Head、Entity、最近变更、seed。
   - `runtime_history`：Timeline、Turn History、Diffs、Snapshot、Checkpoint。
2. 将 `scene.dart` 拆为：
   - `scene_turn_commit`：`commitSceneDialogueTurn` 与提交专用 helper。
   - `scene_state_presence`：场景状态、在场、presence mutation、成员关系。
3. 继续使用 `part` + `mixin ... on _AdventureRepositoryBase`，避免复制 DB 句柄与共享 helper。
4. 每次只移动一个方法组；不修改 SQL、事务边界、幂等键或返回类型。

### 验收标准

- `IAdventureRepository` 接口不变。
- `database_and_repositories_test`、`adventure_turn_commit_atomicity_test`、诊断导出、Adventure 启动测试全部通过。
- 单文件目标不超过约 600 行。
- 事务与 idempotency 行为不变。

### 风险

- 跨 mixin 的 helper 依赖可能增加 base 抽象声明；必须保持方法解析唯一。
- 该拆分是结构性收益，不是功能需求，可在 UI 瘦身后进行。

---

## 3. KeyVault 升级为平台凭证库

> **状态：已完成（2026-11-18）。** 用户已确认接受安全模型变化与回退策略。
>
> - 新增 `SecureKeyStore` 抽象与三个实现：`FlutterSecureKeyStore`（平台凭证库）、
>   `EncryptedDatabaseKeyStore`（KeyVault 回退 / 迁移源）、`MigratingSecureKeyStore`（主从编排）。
> - `SettingsProvider` 全部 Key 读写改经 `MigratingSecureKeyStore`；平台写入成功才删除数据库密文，
>   失败则保留密文并可继续使用；同一 Provider 的读/迁移/写/删串行化，且对停滞的平台调用有 2s 有界等待。
> - 诊断只记录操作名与异常类型，不含明文、密文或 Token；新增测试确保这一点。
> - 文档：`docs/design/api-key-storage.md`。
> - 测试：`test/unit/secure_key_store_test.dart`（10 例，含并发迁移/保存、不可用回退、日志脱敏）。
> - 全量 `flutter test` 4252 passed / 7 skipped，`flutter analyze` 无问题。

### 未完成内容（历史记录）

- 当前 `KeyVault` 是**应用层混淆加密**：PBKDF2 密码与 pepper 编译在应用中，不是 OS Keychain/Keystore，也不是设备绑定。
- 已完成 v2 双密钥与旧格式后台迁移，但安全模型仍是「读取数据库 + 逆向应用可恢复」。

### 完成方案

1. 新增 `SecureKeyStore` 抽象：
   - `read(provider)`
   - `write(provider, value)`
   - `delete(provider)`
   - `isAvailable()`
2. 生产实现优先使用 `flutter_secure_storage`；不可用时回退 `KeyVault`。
3. 迁移流程：
   - 启动加载时优先读 secure storage；
   - 若只有 `api_keys` 中的密文，解密后写入 secure storage；
   - 写入成功后删除或标记数据库密文，避免双写歧义；
   - 失败时保留数据库密文，下次启动重试。
4. 平台策略：
   - Android/iOS/macOS：系统 Keychain/Keystore。
   - Windows/Linux：使用插件支持的后端；不可用时明确回退并记录诊断。
5. 测试：
   - Fake secure store 的读写/删除/不可用回退。
   - 旧 KeyVault 密文 → secure storage 迁移。
   - secure storage 不可用时仍能使用旧路径。
   - 并发保存 Key 与迁移不互相覆盖。

### 验收标准

- 现有用户 Key 不丢失，迁移后仍可正常请求。
- `flutter analyze` 与 KeyVault/设置相关测试通过。
- 日志不输出 Key 明文、密文或完整 Token。
- 文档明确说明平台凭证库与 SQLite 密文的主从关系。

### 风险

- 多平台插件行为差异较大，Linux 可能依赖 libsecret。
- 需要产品确认是否接受「安全模型变化」及回退策略。

---

## 4. Anthropic 备用适配器去留

> **状态：已完成（2026-11-18），采用方案 B。** 用户已确认产品范围。
>
> - `LLMProvider` 新增 `anthropic`：默认 base URL `https://api.anthropic.com`、
>   `chatCompletionsPath` 为 `/v1/messages`、`modelsPath` 为 `/v1/models`，
>   并纳入 `cloudProviders` 与设置页 Provider 选择。
> - `ModelCapabilityRegistry` 新增 `claude-sonnet-4-5` 能力条目与 Anthropic 模型列表；
>   设置页与模型选择页使用下拉，DeepSeek 的 picker 列表保持原样。
> - Anthropic 分支补上 `message_start` 的 input token 解析；请求/响应协议复用既有
>   stream、取消与错误映射实现。
> - 契约测试：`test/services/anthropic_messages_contract_test.dart`（路径、headers、
>   system prompt、SSE 增量与用量、401/429/500 映射、取消）。
> - 全量 `flutter test` 4252 passed / 7 skipped，`flutter analyze` 无问题。

### 未完成内容（历史记录）

- `usesAnthropicMessagesApi` 生产恒为 false。
- `_doSendAnthropicStreamDetailed` / `_extractAnthropicSystemPrompt` 约 370 行，仅由 `@visibleForTesting` seam 与 C6 测试覆盖。
- 当前适配器仍复用 `chatCompletionsPath`（`/chat/completions`），并非真实 Anthropic `/v1/messages` 端点。

### 完成方案（二选一）

**A. 删除**
- 删除 `usesAnthropicMessagesApi`、`forceAnthropicMessagesApi`、`_doSendAnthropicStreamDetailed`、`_extractAnthropicSystemPrompt`、对应 header 分支与 C6 测试。
- 保留 OpenAI 兼容路径与其测试。

**B. 正式支持**
- 增加真实 Anthropic provider 配置、base URL、`/v1/messages` 路径与模型能力条目。
- 增加 Provider 设置 UI。
- 增加 mock HTTP 契约测试：请求路径、headers、system prompt、SSE 事件、取消与错误映射。
- 修复当前 `chatCompletionsPath` 复用问题。

### 验收标准

- 删除路径：相关测试移除后全量相关套件绿灯，无残留引用。
- 支持路径：真实端点契约测试通过，Provider 可选择，取消/超时/错误映射与 OpenAI 路径一致。

### 风险

- 这是产品范围决策，不应由重构自行决定。

---

## 5. 审计中「建议保留」的静默路径

> **状态：按计划保持现状（2026-11-18）。** 未新增逐点 `debugPrint`，现有降级返回值与
> 安全语义不变；新增的 `SecureKeyStore` 诊断只记录操作名与异常类型。

### 未完成内容

以下路径当前按设计静默降级，未改为日志/诊断：

- `resource_lifecycle_reconciler.dart` 的 `_ignoreFailure`
- `tts_model_manager.dart` 的 best-effort cleanup
- `database_service.dart` 的 reset / backup 恢复辅助路径
- `key_vault.dart` 解密失败返回 null/空
- read_aloud 通过 `_markUnavailable` / `_fail` / error callback 上报的路径

### 完成方案

- 默认不改。
- 若未来要求「所有 catch 可观测」，统一引入 debug-only 诊断通道，而不是逐点 `debugPrint`。
- KeyVault 不得打印异常细节或密文，避免形成解密 oracle。

### 验收标准

- 不改变现有降级返回值与安全语义。
- 不引入敏感信息日志。

---

## 6. 全量回归与真机验收

> **状态：部分完成（2026-11-18）。**
>
> - 全量 `flutter test --no-pub` 与 `flutter analyze --no-pub` 已在每次改动后执行并通过。
> - 当前环境只有 Linux 桌面设备（`flutter devices` 未发现 Android 设备或模拟器），
>   因此 Android 真机走读与 release 签名/ARM64 APK 校验仍待在有设备的环境执行。

### 未完成内容

- 最近阶段只运行了定向测试（约 259 个用例），未运行全量 3400+ 测试。
- Android 真机验收仍未完成。
- 未执行 release 构建/签名校验。

### 完成方案

1. 运行 `flutter test --no-pub` 全量套件；记录原有失败与本次引入失败。
2. 运行 `flutter analyze --no-pub`。
3. Android 真机走读：
   - 首次启动 / 语言与 API 设置
   - Adventure 创建与流式回合
   - Resource Library / Studio 生成与恢复
   - Runtime State Hub
   - 朗读 / 神经 TTS 下载与回退
4. 执行现有发布脚本验证签名与 ARM64 APK。

### 验收标准

- 全量测试通过，或失败项有明确基线归属。
- 真机清单逐项记录结果。
- 发布构建与签名校验通过。

### 风险

- 全量测试耗时较长；网络/模型依赖测试可能需要跳过或显式标记。

---

## 7. 远端同步与发布

> **状态：未授权（2026-11-18）。** 用户本次确认仅本地提交，未 push、未创建 PR。

### 未完成内容

- 阶段 1–5 的 commit 均在本地，未 push。
- 未创建 PR、未更新远端分支、未发布新版本。

### 完成方案

1. 用户明确授权后 push 当前分支。
2. 创建 PR，附带阶段 1–5 的变更摘要与验证结果。
3. CI 绿灯后合并。
4. 需要发布时按 `docs/releases/` 流程生成 Android ARM64 版本。

### 验收标准

- 远端分支与 PR 状态符合授权范围。
- CI 通过。
- 发布记录包含版本、签名、产物与验收状态。

### 风险

- 未经明确授权不得 push、创建 PR 或发布。

---

## 建议执行顺序

1. 全量回归基线（第 6 项）——先确认当前健康度。
2. UI 瘦身（第 1 项）与 Repository 再拆分（第 2 项）——结构收益。
3. KeyVault 平台凭证库（第 3 项）——需要安全模型决策。
4. Anthropic 去留（第 4 项）——需要产品决策。
5. 真机验收与发布（第 6–7 项）——最后执行。

以上均为可选后续，不影响当前阶段 1–5 的已交付结果。
