# AI 最近冒险侧栏实施规格

Status: ACCEPTED
Acceptance Mode: Independent Review

## 基线与根因

基线：main / 5a60844；初始工作树干净，baseline flutter analyze PASS。
现有 MainSidebar 将导航和全部历史置于同一个 ListView，仅 full 模式显示历史；历史按创建时间排列，条目直接调用物理删除；选中仅在聊天页面生效。已有 AdventureProvider / Repository 是唯一数据 authority，Trash 支持 legacy marker、恢复和保留期清理。

## 范围与实现

- 保留探索、资料库、回收站、当前状态、当前冒险上下文导航、新建冒险和设置。
- 顶部品牌及导航固定，底部操作固定，独立 Expanded 最近列表滚动；full 和 compact 显示文字历史，rail 和手机 Drawer 提供 History 入口 Sheet，不改变断点。
- 最近活动使用既有 updated_at / messages.timestamp / created_at，倒序排列并以今天、昨天、过去 7 天、更早分组；无 schema 变更。打开和成功消息持久化刷新列表。
- 最近行单行省略、选中 tint 与 leading indicator；桌面 34px，触控与字体缩放允许增高；hover、focus 显示现有 more SVG 菜单，支持重命名和移至回收站。
- 新增最小 Repository rename/touch 与 Trash 入口，Provider 负责当前冒险安全退出及列表更新。Trash marker 使用 adventure:<id> 命名空间，active 查询过滤 marker；恢复保留全部 Adventure 数据，永久清理所有 owned rows。
- 首页保留最近 Adventure 主 CTA，收敛重复历史信息。

## 数据保护与禁止范围

不得复用 physical delete 作为 sidebar 移入回收站；不得改 schema、LLM、State System、Narrative、Resource authority、sidebar breakpoint，或清空数据库。现有异常清理的 physical delete 路径保持。临时 mutation 必须恢复。不得 push。

## 验收

真实 SQLite 测试证明 activity 排序、旧时间 fallback、rename、trash、restore、purge（包含消息与 owned rows），并证明 trash 期间 active 列表/读取不可见。
Widget 测试覆盖空列表、long title ellipsis、selected（含上下文页）、恢复点击、hover/focus 菜单、rename/trash、wide/medium/rail、手机 History Sheet、大量历史只滚动recent且固定导航与底部不移位。
使用项目 responsive helper 验证 320/360/390/412/768/1280，含字体缩放。执行 dart format .、flutter analyze、flutter test、git diff --check；由不同 Agent 进行 Independent Review，修复全部 Blocker/Major 后提交。

## 实施与定向验证记录

UI / Provider 实施完成，待独立审核及 root 全量门禁。

- MainSidebar 顶部导航与底部操作固定；RecentAdventureList 独立滚动，hover 显示Scrollbar；full/compact 展示历史，rail/手机入口使用Sheet。
- 日期采用本地日历边界；row桌面实际34px，touch48px并支持字体缩放。SVG more菜单对hover、键盘focus和触控可达。
- Rename dialog由自身State持有TextEditingController，避免退出动画读已销毁controller。
- 手机320×568已打开Adventure和2x字体下保留全部操作，精简分组heading为divider，避免固定导航溢出。
- Provider开放rename、mark opened、Trash操作；Chat await后复核当前Adventure，避免trash(A)完成时重置新打开的B。
- 首页保留主继续CTA、移除其余重复历史，并将相关删除入口统一为Trash。
- 2026-10-04 `flutter test --no-pub test/widget/recent_adventure_sidebar_test.dart`：11 PASS；包含全部required viewport、active Adventure、2x字体。
- Recent / rail / dashboard sidebar / trash sidebar组合定向测试：62 PASS；实际行高、键盘Tab、hover菜单、rename退出、Trash、日期分组、150条历史滚动固定坐标已覆盖。
- `git diff --check` PASS。最终format / analyze / full tests与数据层真实SQLite门禁由root汇总，不以本记录代替完整验收。

## 最终验收（2026-10-04）

Acceptance Mode: Independent Review。审核上下文 `/root/plan` 未参与实现；最终 BLOCKER = 0、MAJOR = 0、MINOR = 0。

| 用户要求 | 当前实现与验证证据 |
| --- | --- |
| 保留导航、当前状态下最近冒险 | MainSidebar 保留六个固定入口；当前状态后为最近区域/手机与 rail 的历史入口，上下文导航继续保留 |
| 唯一数据源、活动排序、恢复与 selected | 既有 Repository → AdventureProvider → ChatProvider；真实 SQLite 与 sidebar 测试覆盖活动倒序、稳定排序、打开、当前上下文选中 |
| ellipsis、hover 菜单、重命名、Trash | RecentAdventureList 复用 AppActionMenu/SVG；实际桌面行高 34px，键盘与触控可达；真实 DB 重命名、标记、恢复、永久删除及事务回滚通过 |
| 四个时间分组 | 今天/昨天/过去 7 天/更早；旧本地无 offset 时间与 UTC 正确归一化，午夜回归通过 |
| 固定顶底与独立滚动 | 150 条历史实际滚动前后顶部/底部坐标不变；仅最近区域持有 ScrollController，Scrollbar 滚动或 hover 显示 |
| 响应式与可访问性 | 原 600/1100 断点未改；wide/medium 列表、rail/手机 Sheet；320/360/390/412/768/1280，当前冒险、未配置服务、2x 字体通过 |
| 首页主 CTA 与信息收敛 | 保留继续未尽冒险主卡片，移除重复历史列表；首页相关删除也走 Trash，取消不写与恢复立即重现通过真实持久化测试 |
| 架构与数据边界 | 未修改 schema、依赖、State/Narrative/LLM authority；复用 existing Trash marker/retention，保留全部数据直至显式永久删除/到期；v29 无 Trash 表读取兼容通过 |

最终门禁：

- `dart format .`：811 个文件，0 个额外格式化变更。
- `flutter analyze`：No issues found。
- `flutter test`：3297 PASS，2 skipped（与基线跳过数量相同），exit 0。
- `git diff --check`：PASS。
- 独立最后界面/菜单/首页/恢复组合：37 PASS；独立旧库迁移组合：20 PASS。

全量检查发现的旧库缺 Trash 表、旧首页删除语义及 raw menu 违背统一 kernel 均已修复后重跑；未删除、跳过或放宽原测试。独立审核中发现的时区、rename controller 生命周期、异步切换以及未配置服务布局问题均已有回归验证。没有遗留 BLOCKER/MAJOR，没有 schema 迁移或新数据 Authority。验证使用测试临时数据库与 Widget viewport，未进行各平台设备实机测试。仅创建本地提交，不 push。

### 全量回归发现后的修复

- Recent操作菜单改为既有AppActionMenu，全部architecture门禁通过，保持34px行高和键盘/hover交互。
- 将底部未配置状态合并至Settings的可访问tooltip，覆盖已打开Adventure、未配置、2x字体的全部required viewport，解决320×568及1280×800的固定结构高度溢出。
- Default ChatProvider兼容构造复用DatabaseService已有Trash assembly；原library bridge与兼容AdventureRepository共用service装配，避免只有Riverpod路径可移入回收站。
- 首页旧回归升级为真实SQLite：保留长标题/主CTA；确认框及取消不写Trash；确认后冒险及消息仍在数据库；通过现有TrashRuntime恢复并立即重现唯一Adventure列表。
- UI、Dashboard与全部architecture组合90 PASS（/tmp/lt-recent-ui-more4.log）。此前挂起的旧测试session已停止，未修改architecture allowlist或削弱生产断言。
