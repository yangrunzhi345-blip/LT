# 状态 UI 展示净化审计报告

## 审计范围

检查 Dashboard、角色和世界状态卡片、Turn 历史与详情、时间线与详情、初始状态、实体历史、比较、检查点以及编辑页面。重点搜索实体 ID、状态路径、枚举名、生命周期码、`causeType`、提交 ID 和修订号的直接渲染。

## 修复结果

| 区域 | 处理 |
| --- | --- |
| Dashboard / 状态卡片 | 角色名和实体类型回退到本地化通用名；字段和值通过解析器展示；移除普通卡片中的修订号 |
| Turn / 时间线 | 变更改用字段标签和值标签；隐藏实体 ID、路径、原因码、重要性枚举和版本范围 |
| 初始状态 / 实体历史 | 动态实体使用通用实体名；历史项使用字段标签和值标签 |
| 比较 / 检查点 | 比较结果和检查点页面不显示实体 ID、路径和版本号；修订号仅作为内部查询参数 |
| 编辑页 | 未知字段不回退到路径；标题使用实体类型通用名；输入控件保留业务值编辑能力 |
| 本地化 / 守卫 | 六个 ARB 增加通用标签和值；加入源码架构守卫、解析器单测和 widget 泄漏回归测试 |

## 验证

- `flutter gen-l10n`
- `dart format`（变更文件）
- `flutter analyze`
- `flutter test test/architecture/runtime_state_presentation_guard_test.dart test/unit/runtime_state_presentation_test.dart test/widget/runtime_state_presentation_leak_test.dart`

上述定向测试全部通过。剩余技术字段仍可能出现在日志、数据库、内部导航参数或显式的开发工具中；这些不属于普通状态 UI，本次没有改变其运行时权威性。

## 第二轮泄漏复核

针对旧数据库中的 `Turn settlement runtime changes`、`Narrative runtime changes`、`scene_dialogue`、`res_cre_*` 和 `custom_attributes.detected_*` 增加了 timeline detail fixture。`summary` 不再作为普通 UI 文案；cause 只经过集中映射；自定义属性优先读取冻结角色卡、冒险配置和动态成员中的 `id → name` 元数据，历史元数据缺失时显示“状态变化”，不会显示“未知状态: 数值”。

最终门禁：Raw summary exposure PASS；Raw cause exposure PASS；Raw entity ID exposure PASS；Raw path exposure PASS；Raw enum exposure PASS；Legacy DB sanitization PASS；Custom attribute label resolution PASS；Turn-first presentation copy PASS；Architecture guard PASS；Widget leak tests PASS；Analyzer PASS；Full tests PASS（2251 passed，1 skipped）。
