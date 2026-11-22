# Phase 11 当前整改规格

基线：`d48d2ad`；依据本次附件要求，历史各轮同名问题编号以附件语义为准。

## 范围与验收

- P11-B1：手动创建初始章节时，在同一生产事务内创建真实空正文段落；世界观、角色、NPC 均通过真实 SQLite、生产 Provider、Router 的创建、编辑、保存、数据库回读测试。
- P11-M2：创建和 Studio 返回后，页面仍存活才重新加载资源；保留搜索与类型筛选。详情路由不能提前完成资源库等待的 Future。
- P11-M1：复用统一用户消息映射，覆盖 Section、Part、ResourceTree；持久化 validationMessage 必须经过映射；覆盖空章节、缺正文、超限。
- P11-C1：生产装配 Widget 测试不得替换 runtime；仅隔离临时数据库和外部平台依赖。
- P11-C2：测试从实际 MediaQuery 复制并保留 size、padding、viewInsets；覆盖 320×568、1.6 字体、240 键盘、安全区及真实输入、滚动、提交。

## 验证与边界

执行定向回归、dart format、flutter analyze、flutter test，记录实际结果。保护已有未跟踪文件，不推进 Phase 12，不删除历史失败记录。更新 remediation report 并提交；最终 ACCEPTED 由独立验收决定。
