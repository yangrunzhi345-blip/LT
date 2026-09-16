# Phase 12 — 旧系统删除与最终回归执行方案

## 目标与交付物

在新路径已覆盖全部调用方并经过迁移验证后，删除固定 AI 生成模式、重复入口、独立 prompt/保存逻辑、固定字段编辑 UI、废弃兼容层和重复校验。统一资源系统成为唯一正式实现。

## 唯一代码范围

- 删除已无调用方的旧页面、controller、coordinator、prompt builder、validator 和固定编辑 draft。
- 停止旧表写入；在至少一个稳定版本兼容窗口后才考虑 schema 清理。本阶段默认保留只读 legacy 数据，除非独立 migration 证明可回滚。
- 收敛 `LlmTask.worldviewFast/worldviewDeep/importExtraction` 等旧任务，只保留仍被其他业务真实使用者。
- 更新路由、providers、依赖注入、测试、文档和 diagnostics。

## 删除前审计

对每个候选符号执行 `rg`，覆盖动态 route、provider、测试、平台代码、migration 和历史数据 reader。必须建立“旧能力 → 新能力 → 验证证据”矩阵；任何无替代证据的候选不得删除。

重点候选包括：

- `WorldviewDetails.moduleKeys` 驱动的新建/编辑逻辑（兼容 parser 可暂留）。
- `DetailedWorldviewGenerationCoordinator`、`DetailedCharacterGenerationCoordinator` 的旧整套流程。
- `worldview_ai_import_page.dart`、`resource_card_ai_import_page.dart` 的独立创建语义。
- `ResourceLibraryImportController` 等重复 orchestration。
- `ILibraryRepository` 中只服务旧表写入的方法。

## 回归矩阵

- 创建：AI/手动、文本/文件/已有资源参考、三种资源类型。
- 生成：规划、多 Part 流式、暂停恢复、取消、重试、请求切换。
- 编辑：局部重写、扩写、压缩、移动、删除、恢复、并发冲突。
- 数据：v30 升级、迁移重跑、损坏 JSON、自动保存、revision、回收站。
- Runtime：readiness、旧 ready fallback、Adventure snapshot、语义检索。
- UI：全部规定 viewport、长文本、大字体、SafeArea、键盘和桌面。
- 异常：断网、非 2xx、限流、无效 JSON、流中断、应用重启。

## 验证命令

执行定向 migration/repository/coordinator/widget tests 后，再运行：

```text
dart format .
flutter analyze
flutter test
git diff --check
```

按平台风险至少构建 Linux/Windows/Android 中实际受影响目标；移动 UI 必须以 Widget viewport 测试提供自动化证据。

## 最终验收

- 所有正式创建入口均进入同一 pipeline，旧流程无可达路由和 provider 调用。
- 生产写入只落统一 Resource/Section/Part、revision、job/readiness 体系。
- 全仓搜索无重复容量常量、巨型 JSON 资源生成 prompt、每 chunk 数据库写入或旧固定字段新建 UI。
- v30 真实样本升级后内容、关系、Adventure 与检索行为可验证，无数据丢失。
- 删除清单、测试结果、已知风险和回滚方式写入最终提交说明；一个逻辑清理对应清晰 commit。

## 回滚

代码回滚不得依赖降级数据库。保留 legacy 只读列/表和 migration marker；若新路径出现 Blocker，发布修复版恢复兼容 adapter 读取，不得清空或覆盖用户统一资源数据。
