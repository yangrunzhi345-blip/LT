# Phase 10 — Assembly Readiness 组装就绪系统执行方案

## 目标与交付物

将“用户保存的最新创作版本”与“Adventure 可安全消费的版本”解耦。任何 Resource 都有 latest head 与可选 assembly revision；Runtime 只能读取通过验证的 assembly revision。

## 唯一代码范围

- readiness 状态：preparing、ready、failed、stale；记录 head revision、assembly revision、验证结果和时间。
- assembly builder：把内容树转换为 Adventure snapshot、world entries/检索文档及角色运行时核心字段。
- 超限 head 触发压缩准备；正常 head 通过验证后可直接发布为 assembly revision。
- Adventure Wizard/场景组装读取 readiness，必要时等待、显示错误或选择上一个 ready revision。

## 组装规则

- builder 只读取不可变 revision，构建期间 head 改变则结果标记 stale，不能覆盖新状态。
- 世界观只把允许进入 canon 的节点转换为上下文；角色 system prompt/first message 等从明确 metadata 来源构建。
- semantic index 以 assembly revision/content hash 更新，失败不得让旧索引与新 revision 混用。
- 没有 ready revision 时阻止启动并给出可理解提示；存在旧 ready revision 时由用户明确选择。

## 主要修改文件

- 新 readiness model/repository/coordinator
- 新 resource assembly builder 与 adapter
- `AdventureSetupController`、Wizard/start boundary、Adventure config snapshot
- world entry/embedding 同步服务
- readiness race、旧版本选择和端到端组装 tests

## 测试与验收

- NORMAL head 可完成 ready；OVERFLOW head 进入 preparing 并等待压缩候选。
- 组装期间 head 更新时旧任务不能将状态写成新 head ready。
- 无 ready revision、准备中、失败、有旧 ready revision 四种 Wizard 分支均有测试。
- 创建 Adventure 后 snapshot 固定，不因资源后续编辑静默变化。
- 语义检索 fixture 证明索引只对应所选 assembly revision，旧存档继续可读。

## 不做事项

不重新设计资源库信息架构，不移除旧兼容路径；这些留给 Phase 11/12。
