# Android 真机验收待解决问题

- 生成时间：2026-11-18 20:15 +0800
- 来源：Android 真机验收（第 6 项）
- 验收设备：vivo V2361A / Android 16（API 36）/ arm64
- 构建：`1.3.02-debug`（applicationId `com.example.lt_dialogue.debug`）；
  release `app-release.apk` 55.0 MB，仅 arm64-v8a，v2/v3 签名与证书 pin 校验通过
- 代码基线：`main @ 55d0985`（全量 4253 passed / 7 skipped，`flutter analyze` 无问题）

本文件只记录**需要解决的问题**与验收标准，不包含已通过的验收项（见
`docs/plan/remaining-work-2026-11-18.md` 第 6 项）。

---

## P1（MAJOR，安全）：输入法学习并展示 API Key

### 现象

在设置页填入 API Key 并保存后，进入冒险会话，在普通输入框输入英文单词时，
系统输入法联想栏把该密钥当作「已学习词」展示出来。

### 影响

- 密钥被输入法词库收录，可能随输入法云同步离开设备，等同凭证外泄风险。
- 不涉及应用日志或数据库明文：问题出在系统输入法与 `TextField` 的输入属性组合。

### 复现步骤

1. 设置 → 生成 → 模型提供商与 API 配置 → 填入任意 API Key（`sk-...`）。
2. 返回探索页，进入一个冒险会话。
3. 点击底部输入框，输入一个普通英文单词（例如 `Look`）。
4. 观察输入法联想栏出现完整 Key 串。

### 代码位置

- `lib/core/widgets/app_text_field.dart:110-116`：仅设置 `obscureText`，
  未设置 `autocorrect` / `enableSuggestions` / 密码类 `keyboardType`。
- `lib/features/settings/presentation/widgets/provider_config_section.dart:425-432`：
  API Key 使用 `AppTextField(isPassword: true)`。

### 修复要求

- `AppTextField` 在 `isPassword == true` 时强制：
  - `autocorrect: false`
  - `enableSuggestions: false`
  - `keyboardType: TextInputType.visiblePassword`（或等价密码输入类型）
- 普通输入框行为保持不变；禁止为了修复而全局关闭联想。
- 不得新增任何打印/日志输出 Key、密文或 Token。

### 用户侧处置（文档需提示）

清理输入法「已学习词 / 个人词典」，并确认输入法未开启云端同步。

### 验收标准

- 填入 Key 后，在普通输入框输入英文，联想栏不再出现 Key 内容。
- 新增 Widget 测试：密码模式下 `EditableText.enableSuggestions == false`
  且 `autocorrect == false`。
- `flutter analyze` 与相关设置/输入测试通过。

---

## P2（MINOR，UI）：首页存档时间显示原始 ISO/UTC

### 现象

首页「继续未尽的冒险」卡片显示：

`存档于 2026-11-18T11:57:32.098354Z`

资料库同一数据却显示本地化格式（如 `11月18日 19:34`）。

### 代码位置

- `lib/features/adventure/presentation/home/widgets/dashboard_recent_saves.dart:109`
  直接取 `item['updated_at']` 并交给 `l10n.dashboardSavedAt(updated)`。

### 修复要求

- 将 `updated_at` 解析为 `DateTime` 后按本地时区格式化，复用项目现有时间格式
  约定（与资料库保持一致）；解析失败时回退为不显示时间，而不是显示原始串。
- 不修改数据库字段或写入逻辑。

### 验收标准

- 首页不再出现 `T...Z` 形式的原始时间。
- 新增/更新 Widget 测试：给定 UTC 时间串，断言渲染为本地化文本。
- `flutter analyze` 与相关首页测试通过。

---

## P3（MINOR，文案）：Runtime Hub 空态复用了「回收站是空的」

### 现象

- 历史与时间线空态显示：`回收站是空的: 历史与时间线`
- 实体列表空态同样以「回收站是空的」开头（角色/世界状态为空时）。

### 代码位置

- `lib/features/adventure/presentation/state/runtime_hub_views.dart:257`
  （实体空态）与 `:445`（时间线空态）。

### 修复要求

- 为以下空态新增独立 l10n key（6 种语言 ARB 同步）：
  - 角色状态为空
  - 世界状态为空
  - 时间线为空
- 移除对 `emptyRecycleBin` 的复用；不得影响真正的回收站空态文案。

### 验收标准

- 上述空态不再包含「回收站」字样。
- `flutter gen-l10n` 后 6 个语言文件同步，`flutter analyze` 通过。
- 相关 Runtime Hub Widget 测试通过。

---

## P4（待定，非缺陷）：真机尚未覆盖的链路

- 神经 TTS 实际模型下载：只在设备上验证了「需手动下载模型 / 已安装 0 个 / 系统语音可用」
  的回退状态，未触发实际下载（体积大、依赖网络）。
- Resource Studio AI 生成与恢复：未执行（会消耗用户 API 额度）。
- 如需覆盖，需明确授权使用额度并允许下载模型。

---

## 范围边界

- 仅修改输入控件属性、首页时间格式化、Runtime Hub 空态文案与对应 l10n/测试。
- 不改 Provider 选择逻辑、SQLite schema、流式管线、凭证存储实现。
- 不在此任务中引入无关重构或全量 UI 样式调整。

## 建议顺序

1. P1（安全，优先）
2. P3（文案，改动小）
3. P2（格式化）
4. P4（需授权后另行安排）
