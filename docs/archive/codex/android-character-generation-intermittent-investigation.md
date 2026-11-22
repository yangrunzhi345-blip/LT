# Android 角色生成间歇性失败调查

Status: ACCEPTED — diagnostic repair only。Acceptance Mode: Independent Review。原始 Android release 间歇性故障仍 UNRESOLVED / BLOCKED。

本文件为调查记录及用户批准的诊断修复规格，不是原始间歇性故障的根因修复或验收报告。

## Scope 与基线

- 用户报告：同一 Android APK 世界观生成正常，角色生成失败；随后补充角色又成功，故障具有间歇性。
- 后续用户证据：名为“二号角色”的生成再次报“资源生成失败，请重试。”；用户明确确认失败发生在正文阶段。尚不知道具体失败 Part、已完成正文量或后续成功的操作方式。
- 调查基线：`main`，HEAD 与 fetch 后的 `origin/main` 均为 `acb642b014b3939049a32f7a42d062e07333be09`。
- 调查开始时工作区干净；调查初期仅新增本文档。用户后续明确批准诊断修复，已在下述范围修改业务代码、本地化及测试。
- Scope：Resource Studio 的世界观与角色生成、解析、校验、持久化、生命周期、重试及错误展示。
- 禁止范围：放宽正确的 invariant、绕过持久化、吞异常、禁用 R8、角色专用硬编码、架构降级、清空数据库、版本与依赖调整、发布 Release/APK。

## 已确认的当前调用链

1. 世界观入口 `lib/screens/resource_library/worldview_ai_import_page.dart` 与角色入口 `lib/screens/resource_library/character_card_edit_page.dart` 均提交 `ResourceStudioCreationDraft`。
2. `ResourceStudioController.createAndStart` 经 `ResourceStudioRuntime` 进入 `ResourceAiCreationOrchestrator`；创建会话持久化后调用统一的 `BlueprintPlanner`。
3. Blueprint 由统一 `BlueprintPromptBuilder` 构造；`AiGeneratorLlmGateway.rawCompletion` 调用统一 `LLMService`。规划输出经过 `BlueprintParser`、预算归一化及 `BlueprintValidator`，再持久化。
4. Blueprint 确认在事务内建立 ResourceTree 占位节点与 Part 任务；`StreamingResourceGenerationService` 启动正文生成，完整生成明确传入 `maxConcurrentParts: 1`。
5. `PartGenerationCoordinator` 在事务取得 attempt 身份与序号，构造统一 Part prompt。Gateway 流式返回 NDJSON，`ModelGenerationPatchDecoder` 绑定客户端身份，accumulator 累积正文。
6. `PartGenerationValidator` 校验身份、非空正文与单 Part 容量。`PartGenerationTaskRepositoryImpl.commitPartContent` 在事务中校验 source token 并提交正文及相关状态。
7. 生命周期与事件驱动 Studio；失败段落重试沿用任务/attempt 持久化机制。

这是已读取的调用链结构，不证明本次故障已沿上述链路执行到任何特定阶段。

## 差异与诊断限制

- 第一个静态输入差异在入口：角色类型、名称、预算、参考资料不同。角色编辑器把世界观与关联角色文字拼入参考资料；此入口没有传入 typed relationship draft 或 origin worldview ID。不能将这一差异直接判为生成失败根因。
- 规划 prompt 按资源类型改变内容要求；JSON、ID/DAG 校验与规划持久化复用同一实现。
- Part 的 NDJSON 协议、解析器、正文校验与提交实现共享，不存在因角色类型改用另一套 Part parser 的证据。
- `GenerationDiagnostics.enabled` 仅在 debug/profile 启用；release 的诊断缺口不等于 release 的生成行为缺陷。
- Studio 对未分类异常使用通用错误。Part 失败记录也把多种异常归为通用生成失败；目前无法从用户看到的提示反推出异常层级。
- 用户提供的文案准确对应 `resourceErrorGenerationFailed`。正文服务在 required Part 未全部成功及外层异常两条路径都发出同一个 `resourceGenerationFailed`；即使此前已发出 `ValidationFailed`，最终 `GenerationFailed` 仍覆盖 UI 错误。已确认的是诊断信息损失，不是本次生成失败的原始根因。
- 规划默认有 60 秒超时。统一文本接口会拒绝 incomplete/truncated response。这是可能产生间歇性失败的路径，尚无本次失败响应或时间证据，不能据此修改超时或 token 预算。

## 已运行的基线验证

第一组现有测试：41 项 PASS。

- `test/application/resources/part_generation_coordinator_test.dart`
- `test/application/resources/retry_failed_parts_test.dart`
- `test/application/resources/resource_generation_task_repository_test.dart`
- `test/application/resource_library/character_generation_reference_test.dart`
- `test/widget/character_card_manual_save_test.dart`

第二组现有测试：74 项 PASS。

- `test/services/llm_streaming_reliability_test.dart`
- `test/application/resources/blueprint_planner_test.dart`
- `test/integration/resource_generation_soak_test.dart`

覆盖包括角色/世界观规划与生成、真实测试 SQLite 事务路径、失败重试、超时取消、分片/突发流、畸形输出及有界失败收敛。注意：soak rig 的资源类型固定为 worldview，不能宣称已覆盖 Android 角色的间歇性故障。Provider 响应为受控测试输入，不能替代报告中的真实响应。

以上是修复前的历史基线记录。此次诊断修复后的 format/analyze/test、Android ARM64 构建及回归证据见下节；诊断改动以独立 commit 交付，Git 同步结果见最终报告。

## 诊断修复实施与验证记录

Implementation Status: ACCEPTED — diagnostic repair only。Acceptance Mode: Independent Review。

独立审核报告：[android-character-generation-diagnostics-independent-review.md](android-character-generation-diagnostics-independent-review.md)。审核 Agent 独立运行 104 项定向回归及两项 APK 签名/ARM64 脚本，均 PASS；诊断范围内 Blocker = 0、Major = 0。此验收仅针对错误分类与展示，不验收原始实机间歇性失败。

### 已实施范围

- 新增 `lib/application/resources/resource_generation_error.dart`：复用 `ApiError.code`，按明确异常类型和实际 parsing / persistence / lifecycle 操作阶段产生稳定安全 code；未知异常及历史任意字符串为 `unknown`，不按诊断文本猜测类型。
- `part_generation_coordinator.dart` 在失败 attempt 写入时保留安全分类；预算耗尽不再覆盖 task 已记录分类。回调及 accumulator 失败按实际阶段记录，同时保持原始异常 `rethrow`，不丢失 source-CAS conflict / cancellation 类型。未改变重试预算、流读取/预览节流、source token、校验规则或提交顺序。
- `streaming_resource_generation_service.dart` 完整生成终态同时读取同一 failed task 的 Part 与分类；单 Part retry 只有精确匹配本次 `onPartStarted` 捕获的 attempt ID 才使用持久化分类，避免错读其他尝试。终态、校验事件与 session 持久化分类一致；成功后清除相应历史错误。
- `resource_studio_controller.dart` 在重新打开失败会话时恢复 typed error；`resource_studio_user_message.dart` 不再把任意历史诊断字符串作为用户文案。
- `app_error.dart`、`app_error_localizer.dart` 与六种语言 ARB / generated localization 提供 parser、content validation、persistence、lifecycle、provider incomplete 分类文案；API 5xx 使用独立的服务暂不可用文案。UI 仅显示安全类别，不显示响应、正文、原异常、secret 或内部标识。
- 测试修改集中于 `test/application/resources/streaming_resource_generation_service_test.dart`、新 `resource_generation_error_test.dart`、`test/widget/resource_studio_test.dart`；既有 `p0_malformed_ndjson_spin_test.dart` 和 `streaming_generation_lifecycle_recovery_test.dart` 仅将旧通用/预算错误文案断言改为精确稳定分类，并强化 task/attempt 一致性。原预算、dispatch、取消和数据保护断言保持。

### 可复核证据

1. 修复前新增的 network / parser / unknown 三条真实 SQLite 角色回归全部 FAIL：task 分类被预算中文覆盖（`/tmp/lt-diagnostics-red.log`）。修复后初始三条全部 PASS（`/tmp/lt-diagnostics-green.log`）。这证明诊断缺陷，不能证明手机原始失败根因。
2. 回归覆盖角色正文网络/Provider、畸形与部分 NDJSON、空正文、sequence gap、cursor mismatch、真实 SQLite trigger 注入提交失败、lifecycle start/preview、未知异常与 foreign attempt 所有权；检查 attempt/task/session/validation/terminal 稳定分类、失败 retry 与成功 retry 清理。生产 streaming gateway 路径的畸形/partial 与 fallback 均经真实 SQLite，并覆盖成功重试。合法角色/世界观生成及用户 Unicode 内容/cursor 均保持可提交。
3. Studio 重新加载分类恢复、成功清理、原有 late validation event 保护，以及六种 viewport（320 / 360 / 390 / 412 / 768 / 1280 px）与 text scale 1.3 的新错误文案显示；六种真实 supported locale 的无 secret/unknown 区分检查。新增中文脚本 locale 使用 `Locale.fromSubtags`。
4. 第一轮全量在实施补充期间运行，结果为 3418 PASS、2 既有 skip、4 FAIL（`/tmp/lt-diagnostics-full-test.log`）：`turn_settlement_test.dart` stage4 30 秒 timeout；两条旧诊断文案预期；新增 5xx 断言遇到该轮启动时的旧 localizer。该轮含运行中源文件变化，不作为最终验收结果。未放宽 timeout、预算、断言或跳过测试。
5. 上述失败文件加诊断回归精准复测 77 PASS（`/tmp/lt-diagnostics-failed-rerun.log`），包括 turn_settlement stage4。补 production streaming 路径后的 service 文件 31 PASS（`/tmp/lt-diagnostics-streaming-targeted.log`）。
6. 冻结最终代码后 `dart format .` PASS（830 文件，仅任务范围文件实际格式变动）；`flutter analyze` PASS（No issues found）；`flutter test --concurrency=2` 完整全量 PASS：3424 PASS、2 既有 skip、0 FAIL，8m38s（`/tmp/lt-diagnostics-final-full.log`）；`git diff --check` PASS。两个 skip 是既有 Chrome-only backend 测试与未启用 `LT_TTS_REAL_MODEL=1` 的真实模型测试，未新增 skip。
7. `flutter build apk --release --target-platform android-arm64` PASS，Gradle assembleRelease 62.9s，APK 54.6 MB（`/tmp/lt-diagnostics-arm64-build.log`）。本地 `apksigner verify --verbose --print-certs` PASS，v2/v3 签名有效，单一 `CN=LT Android Release` signer；`aapt dump badging` 与 ZIP native library 检查均确认仅 `arm64-v8a`，包含 `libapp.so` / `libflutter.so`。现有版本 1.2.00 (22) 未修改。构建仅供验证，没有上传 APK 或发布 Release。

当前 Git 改动为诊断代码/本地化/回归测试及本调查文档；无数据库 schema、依赖、版本、签名配置或其他子系统改动。已通过上述 Independent Review；诊断改动以独立 commit 交付，Git 同步结果见最终报告。

## 环境证据与未完成项

- 多次 `adb devices -l` 无设备；USB 列表也未发现手机。
- `flutter run --release -d android` 因无匹配设备退出，未实际执行生成。
- 有可用 emulator，但不能直接替代故障真机与相同 Provider/API 条件；用户明确表示无法连接设备。
- 未取得 request 是否发送、HTTP status、response、stream 结束、首次失败 Part、parser/validation/persistence error、lifecycle transition、exception type/stack trace 的本次故障证据。
- 已确定为正文阶段；尚未确定再次成功是段落重试还是新建。

## 已授权的诊断改动

用户在确认正文失败、提供错误文案后，对先修复错误分类与展示的明确提问答复“修复”。该授权允许实施本节的诊断改动；不允许宣称已经解决原始间歇性生成故障。

可审查的最小目标：

- 复用 `ApiError.code` 和现有 locale-neutral `AppDomainError`，按已知异常类型及执行阶段区分网络/Provider、解析、校验、持久化、生命周期；未知异常继续明确标为未知，不按字符串猜类型。
- attempt/task 的失败记录保留稳定分类，终态失败事件保留相同分类，Studio 不再用通用生成错误覆盖先前的具体失败原因；历史记录保持兼容。
- 用户文案只显示安全类别及可理解的处理方式，不显示 raw response、正文、请求头、secret、schema path 或内部 ID。
- 补充角色正文 fault injection、终态错误保留、失败重试后成功清理错误、真实 SQLite 事务及世界观不回归测试；这只能验收诊断改动，不构成本次故障根因验收。
- 对原始生成故障仍要求真实失败证据或明确可重放案例。诊断改动不得更改输出契约、容量/校验 invariant、重试上限、提交顺序、schema 或依赖。

实施位置与要求：

- `lib/application/resources/part_generation_coordinator.dart`：在捕获异常时按类型和实际执行阶段生成安全稳定分类；attempt/task 持久化使用稳定 code，保留 bounded retries 与 cancellation/source token 语义。
- `lib/application/resources/streaming_resource_generation_service.dart`：完整生成与单 Part retry 的终态失败读取实际失败 task 分类；异常分支按实际阶段分类，不能将所有失败重写成通用 code。
- `lib/domain/errors/app_error.dart`、`lib/core/localization/app_error_localizer.dart`、`lib/features/resource_studio/presentation/resource_studio_user_message.dart`：复用现有 AppDomainError/ApiError 分类；按需增加明确且安全的正文 parser、validation、persistence、lifecycle、provider-incomplete 文案，不把原始异常字符串用于 UI。
- 允许新增一个 application/resources 的统一错误分类 helper，前提是没有同等现有实现，且实际供 coordinator/service/Studio 使用。必须显式处理未知 code 与历史诊断字符串兼容。
- `lib/l10n/app_*.arb` 及项目生成的 localization 文件：六种现有语言的安全分类文案；不新增依赖、不改组件布局、不新增图标。
- 测试集中于 application/resources、Studio 已有控制器/widget 测试及 error/localization 测试。必须先证明旧实现会丢失故障类型，再证明修复保留到 task/attempt/session/event/UI，覆盖 retry 成功后错误清理与晚到事件保护。
- 修改前检查子目录 AGENTS；修改后执行 targeted tests、全量 format/analyze/test、diff-check；允许 Android arm64 本地构建，不发布 Release/APK。
- Plan/Execute/Independent Review 职责分离；执行 Agent 提供 diff 与真实验证记录，审核 Agent 只读检查。若有失败返工并重跑。
- 本诊断修复作为独立 commit；只在实际完成并验证后按用户原授权 push origin/main，fetch 确认一致。原始目标在真实证据不足时保持未完成。

验收：network/provider、parser、validation、persistence、lifecycle 的注入故障均有安全不同的提示；未知异常不伪装已知原因；首个确定失败对应的分类不被终态通用事件覆盖；重新加载仍可取得分类；合法角色/世界观成功行为及失败重试不回归；API Key、用户正文和原异常内容不得出现在 UI 或持久化错误字段。真实 SQLite、必要 widget 测试及规定的静态分析/全量测试 PASS 后仅可接受诊断修复。

## 继续调查与实施门槛

1. 优先取得失败阶段、界面错误文字、成功操作与失败操作的差异；不能把一次成功当作故障消失。
2. 若仍无法连接设备，需要已有的安全日志或可重放响应证据；不得索取/记录 API Key、Authorization、Cookie 或其他 secret，不得在报告保留用户正文。
3. 利用证据建立本次故障的确定性复现；对照同一 Provider 的世界观成功路径，确认首次行为分歧。受控 fault injection 只能证明程序如何处理某类失败，不能证明其就是本次根因。
4. 确认首个根因后，补充具体实施文件、最小修复、禁止范围与验收标准，再修改代码。默认职责分离遵循 AGENTS.md；本记录不授权单 Agent integrated acceptance。
5. 必须新增复现本次问题的测试，覆盖世界观成功、角色成功/失败、畸形/部分输出、失败角色 Part 重试与真实持久化；根因涉及 release 时补充对应分支验证。
6. 最终执行用户要求的 `dart format .`、`flutter analyze`、`flutter test`、`git diff --check`，环境允许时执行 Android arm64 release 构建，并作完整 diff review 与验收。
7. 修复及验证完成后创建一个独立 commit、push `origin/main`、fetch 确认 HEAD 等于 origin/main、确认工作区干净。不创建 GitHub Release，不上传 APK。

## 风险分类

- BLOCKER：报告中的实机故障尚未复现、根因与失败层级未确认。
- INFO：本次错误分类丢失与通用终态覆盖已修复并通过上述受控回归；不证明它们是原始正文生成失败的原因。Release 实机响应证据仍缺失。
- 仅诊断修复获得 Independent Review ACCEPTED；原始用户问题仍未解决，不因受控测试 PASS 推定其实机根因已消除。
