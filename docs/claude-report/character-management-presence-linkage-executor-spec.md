# 角色管理 UI 在场状态断链 — 执行规格（可照抄版）

- 状态：**待执行**（本报告只做调查与规格，未修改任何生产代码）
- 作者：claude-opus-5.5
- 日期：2026-09-27
- 报告基线：HEAD `4f5cd16593b000062a941241a54e3b7b34470264`（= `origin/main`，分支 `main`）
- 配套文档：`docs/claude-report/character-management-presence-linkage-report.md`（审计版，讲“为什么错”）
- 本文档：**执行版**，讲“改成什么样”，代码可直接照抄

> 本文档是给执行 Agent 的工单。设计原则：**不要自行推导，不要自行优化，只做本文档列出的改动。**
> 凡本文档未列出的文件，一律不得修改。遇到本文档没覆盖的情况，停下来记录，不要临场发挥。

---

## 0. 开工前必读

### 0.1 唯一恢复现场

以**当前磁盘 working tree** 为唯一恢复现场。当前已有 18 个文件处于未提交修改状态（见 §7）。
这些是前一个 Agent 与本任务的有效工作，**不是脏数据**。

**严禁执行**（无一例外）：

```
git reset            git restore           git checkout -- <file>
git clean            git stash             git rebase
git commit           git push              git tag
```

**允许执行**（只读）：

```
git status --short   git diff              git log --oneline
git show <ref>:<path>                       git branch --show-current
git rev-parse HEAD                          git grep
git worktree add --detach <tmpdir> HEAD     # 仅用于只读基线对比
```

### 0.2 禁止修改的文件清单（硬约束）

以下文件属于权威层，**本任务一律不得修改**。若你认为必须改其中某个文件才能修好问题，
说明方案理解有误——回到 §1 重读，或停下来记录，**不要动它们**：

```
lib/application/adventure/adventure_character_identity.dart   ← 最容易被误改，见 §2.1 警告
lib/models/adventure_config.dart
lib/models/scene_state.dart
lib/models/adventure_runtime_state.dart
lib/providers/adventure_provider.dart
lib/services/repositories/adventure_repository_impl.dart
lib/services/scene_state_proposal_validator.dart
test/widget/resource_library_production_test.dart
```

**本任务允许修改的文件**（只有这 5 个）：

```
lib/features/adventure/presentation/session/screens/scene_character_management_page.dart
lib/features/adventure/presentation/state/runtime_state_hub_page.dart
lib/l10n/app_{en,ja,ko,zh,zh_Hans,zh_Hant}.arb          （6 个 ARB）
lib/l10n/generated/**                                    （由 flutter gen-l10n 重新生成，不手改）
test/widget/scene_character_management_page_test.dart
test/widget/custom_attribute_test.dart
```

### 0.3 明确禁止事项

- 禁止新增/重构：SQLite schema、migration、Repository Authority、Domain 状态模型、LLM、Prompt、
  Streaming、State Commit、新的角色状态权威、新的 Presence Authority。
- 禁止在 Presentation 层复制、缓存或推导第二套角色状态真相。
- 禁止默认 HP=100 / MP=100 / 金币=0 冒充真实状态；禁止按 UI 猜测存活状态。
- 禁止展示 `entityId`、内部 UUID、JSON、SQL、runtime key 或开发者内部字段名。
- 禁止为了让测试变绿而删除测试、放宽断言、或修改无关业务模块。
- 禁止 `git add -A`。若要暂存，显式列出本任务文件。
- **本轮禁止一切 Git 写操作（commit / push / tag / 远端改动）。所有修改留在工作区。**

---

## 1. 问题与本任务目标

角色管理页 `SceneCharacterManagementPage` 的“在场/离场”判定，用错了 ID 空间，
导致主角永远被判为“离场”，并出现一个点了必然失败的“进入场景”按钮。

**本任务要达成的验收目标**（4 条，缺一不可）：

1. 主角永远显示在“当前在场”区段，且**永远不显示**“进入场景”按钮。
2. 进入/离开场景的操作，只对非主角角色生效，且操作后权威数据真的改变。
3. 从管理页进入“状态中心”，不会再出现“管理角色”按钮形成无限跳转。
4. 角色卡片上的属性摘要，能显示自定义属性的真实名称，而不是笼统的“状态变化”。

---

## 2. 根因（简版，够用即止）

### 2.1 主角在权威层叫 `'protagonist'`，在名册里叫角色卡 ID

- 权威 `SceneState.presentCharacterIds` 里，主角存的是**字面量字符串 `'protagonist'`**。
  证据：`scene_state.dart:192` 默认值；`adventure_provider.dart:313`/`:835` 初始化；
  `scene_state_proposal_validator.dart:54` 无条件 `present.add('protagonist')`。
- 名册 `AdventureSelectedCharacter` 里，主角行的 `characterId` 是**真实角色卡 ID**
  （如 `card_abc123`）。证据：`adventure_wizard_screen.dart:1537`、`assembly_create_page.dart:248`。
- `AdventureCharacterIdentity.effectiveId()` 对主角返回的是**角色卡 ID**，不是 `'protagonist'`。

于是下面这行对主角**永远为 false**：

```dart
presentIds.contains(AdventureCharacterIdentity.effectiveId(character))  // 主角恒为 false
```

> ⚠️ **警告：绝对不要修改 `AdventureCharacterIdentity.effectiveId()`。**
> 它同时被运行期实体播种、overlay 键、`resolveRelation`、提示词 `character_id` 使用。
> 改它会让状态挂到错误身份上，属于明令禁止的越界重构。
> 正确做法是**在管理页这一侧适配**，即 §3.1。

### 2.2 管理页与状态中心互相跳转

管理页卡片点击 → 状态中心；状态中心在角色类型下又渲染“管理角色”按钮 → 管理页。
两者都没有停止条件，可无限叠加导航栈。

### 2.3 属性摘要标签被笼统化

`_runtimeSummary` 对白名单（hp/mp/gold/relationship/affinity/energy/level）之外的所有属性键，
一律套用同一个文案 `l10n.runtimeStateChangedState`（“状态变化”），
导致自定义属性无法区分。项目已有正确解析器 `RuntimeStatePresentation.fieldLabelWithMetadata` 未被使用。

**注意**：`RuntimeStatePresentation.fieldLabel` 的 `switch` 中**没有 `'gold'` 分支**，
会落到 `runtimeStateFieldUnknown`。因此现有代码里 `path == 'gold'` 的特判**必须保留**。

---

## 3. 修改规格（逐条照做）

### 3.1 [Blocker] 修复主角分类与进入按钮

**文件**：`lib/features/adventure/presentation/session/screens/scene_character_management_page.dart`

**改动 1**：把 `build` 方法中第 79-82 行的分类循环

```dart
    for (final character in characters) {
      final id = AdventureCharacterIdentity.effectiveId(character);
      (presentIds.contains(id) ? present : away).add(character);
    }
```

替换为：

```dart
    for (final character in characters) {
      // 主角在权威层以字面量 'protagonist' 记录，且校验器无条件确保其在场
      // (scene_state_proposal_validator.dart:54)，因此这里是不可变事实，
      // 不能拿名册的角色卡 ID 去 presentCharacterIds 里查表。
      if (character.isProtagonist) {
        present.add(character);
        continue;
      }
      final ids = AdventureCharacterIdentity.candidateIds(character);
      (ids.any(presentIds.contains) ? present : away).add(character);
    }
```

**改动 2**：`_canEnter`（当前第 264-269 行）增加主角短路：

```dart
  bool _canEnter(
    AdventureSelectedCharacter character,
    List<RuntimeEntityState> entities,
  ) {
    // 主角恒在场，不提供“进入场景”操作：未播种实体时状态未知，
    // 给出必然失败的按钮只会误导用户。
    if (character.isProtagonist) return false;
    return _lifeStatus(_runtimeEntity(character, entities)) == 'alive';
  }
```

**不需要改的部分**：`_characterCard` 里 `action` 的三元表达式（第 167-189 行）逻辑已经正确——
当 `isInScene == true` 时走 `canLeave ? 进入按钮 : null`，而主角上层的 `canLeave: !character.isProtagonist` 为 false，
所以改完分类后主角自然落到 `null` 分支、不渲染按钮。**不要动这段。**

### 3.2 [Major] 断开管理页 ↔ 状态中心的跳转环路

**文件**：`lib/features/adventure/presentation/state/runtime_state_hub_page.dart`

**改动**：在角色类型分支的“管理角色”按钮处（当前第 823-838 行），增加 `!widget.openCharacters` 条件。

将：

```dart
        if (types.contains(RuntimeEntityType.character))
          AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SceneCharacterManagementPage(),
                ),
              ),
              icon: const Icon(Icons.groups_outlined),
              label: Text(l10n.characterManagementManage),
            ),
          ),
```

改为：

```dart
        // openCharacters 为 true 表示本页是从角色管理页进入的；
        // 此时再渲染“管理角色”入口会形成无界跳转，因此只保留单向入口。
        if (types.contains(RuntimeEntityType.character) &&
            !widget.openCharacters)
          AppCard(
            margin: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SceneCharacterManagementPage(),
                ),
              ),
              icon: const Icon(Icons.groups_outlined),
              label: Text(l10n.characterManagementManage),
            ),
          ),
```

> 从会话页正常进入状态中心时 `openCharacters` 为 `false`，入口保留——不要在别处改动这个默认值。

### 3.3 [Major] 属性摘要使用真实属性名

**文件**：同 §3.1

**难点说明（必须按此处理）**：`_runtimeSummary` 当前签名是
`String _runtimeSummary(BuildContext context, RuntimeEntityState? entity)`，
**拿不到 `AdventureConfig`**。禁止把它改成 `static`、禁止用全局变量、禁止内部再读 provider。
正确做法是**由 `build` 读出标签表，沿调用链传下来**。

**改动 1**：在 `build` 中 `config` 已存在的位置（当前第 74 行之后）增加一行：

```dart
    final customLabels = RuntimeStatePresentation.customAttributeLabels(
      config?.allTrackedCustomAttributes ?? const [],
    );
```

**改动 2**：把 `build` 里两处 `_characterCard(...)` 调用（当前第 101-107 行、第 114-120 行）
各增加一个参数 `customLabels: customLabels,`。

**改动 3**：`_characterCard` 签名（当前第 142-149 行）增加参数：

```dart
  Widget _characterCard(
    BuildContext context,
    WidgetRef ref,
    AdventureSelectedCharacter character, {
    required bool isInScene,
    required Map<String, String> customLabels,
    bool canLeave = false,
    bool canEnter = false,
  }) {
```

并在方法内把 `final summary = _runtimeSummary(context, entity);`（当前第 166 行）改为：

```dart
    final summary = _runtimeSummary(context, entity, customLabels);
```

**改动 4**：把 `_runtimeSummary` 整个方法（当前第 296-331 行）替换为：

```dart
  String _runtimeSummary(
    BuildContext context,
    RuntimeEntityState? entity,
    Map<String, String> customLabels,
  ) {
    final l10n = _l10n(context);
    if (entity == null || entity.overlay.isEmpty) {
      return l10n.characterManagementNoData;
    }
    // gold 不在 RuntimeStatePresentation.fieldLabel 的映射表中，
    // 会落到 runtimeStateFieldUnknown，因此这里保留专用文案。
    const preferred = [
      'hp',
      'mp',
      'gold',
      'relationship',
      'affinity',
      'energy',
      'level',
    ];
    final values = <String>[];
    for (final path in preferred) {
      final value = entity.overlay[path];
      if (value == null || value.toString().trim().isEmpty) continue;
      values.add(
        '${path == 'gold' ? l10n.characterManagementGold : RuntimeStatePresentation.fieldLabel(path, l10n)}: '
        '${RuntimeStatePresentation.valueLabel(path, value, l10n)}',
      );
    }
    for (final entry in entity.overlay.entries) {
      if (preferred.contains(entry.key) ||
          entry.value == null ||
          entry.value.toString().trim().isEmpty) {
        continue;
      }
      values.add(
        '${RuntimeStatePresentation.fieldLabelWithMetadata(entry.key, l10n, customAttributeLabels: customLabels)}: '
        '${RuntimeStatePresentation.valueLabel(entry.key, entry.value, l10n)}',
      );
    }
    return values.isEmpty ? l10n.characterManagementNoData : values.join(' · ');
  }
```

> 若第 4 步之后 `flutter analyze` 报 `_runtimeSummary` 有未使用的 `context` 参数警告，
> **不要删除该参数**（`_l10n(context)` 仍在使用），也不要用 `// ignore:` 压制，检查是否抄错了调用点。

### 3.4 [Minor] 补足“可加入当前场景的角色”区段

**文件**：同 §3.1

当前 `away` 列表把「不在场但可进入」与「已死亡 / 状态未知」混在一起，且禁用按钮无任何说明。

**改动 1**：在 `build` 的分类循环之后，把 `away` 再拆成两个列表：

```dart
    final enterable = <AdventureSelectedCharacter>[];
    final blocked = <AdventureSelectedCharacter>[];
    for (final character in away) {
      (_canEnter(character, provider.runtimeEntities) ? enterable : blocked)
          .add(character);
    }
```

**改动 2**：把 `build` 中第二个区段（当前第 108-120 行）

```dart
            const SizedBox(height: 20),
            _sectionTitle(context, l10n.characterManagementJoined),
            if (away.isEmpty)
              _empty(context, l10n.characterManagementNoData)
            else
              for (final character in away)
                _characterCard(
                  context,
                  ref,
                  character,
                  isInScene: false,
                  canEnter: _canEnter(character, provider.runtimeEntities),
                ),
```

替换为：

```dart
            const SizedBox(height: 20),
            _sectionTitle(context, l10n.sceneCharactersAvailable),
            if (enterable.isEmpty)
              _empty(context, l10n.sceneCharactersEmpty)
            else
              for (final character in enterable)
                _characterCard(
                  context,
                  ref,
                  character,
                  isInScene: false,
                  customLabels: customLabels,
                  canEnter: true,
                ),
            const SizedBox(height: 20),
            _sectionTitle(context, l10n.characterManagementJoined),
            if (blocked.isEmpty)
              _empty(context, l10n.characterManagementNoData)
            else
              for (final character in blocked)
                _characterCard(
                  context,
                  ref,
                  character,
                  isInScene: false,
                  customLabels: customLabels,
                  canEnter: false,
                ),
```

> **文案键决策已做出，不要另起新键**：使用**已存在但从未被引用**的
> `sceneCharactersAvailable`（“冒险中可用” / "Available in adventure"）与
> `sceneCharactersEmpty`（“暂无可用角色” / "No available characters"）。
> 这两个键在 6 个 ARB 中**已全部定义**，因此本任务**不需要新增任何 ARB 键**，
> 也**不需要重新运行 `flutter gen-l10n`**。
> 同理，`characterManagementJoined` 保留给“已加入冒险”区段（改用为“不可进入”组），
> `characterManagementPresent` 保留给在场区段。

**改动 3**：让禁用状态可解释。在 `_characterCard` 中，把非在场分支的按钮
（当前第 179-189 行）替换为：

```dart
        : (canEnter
            ? IconButton(
                tooltip: l10n.sceneCharactersEnter,
                icon: const Icon(Icons.login_outlined),
                onPressed: () => _mutatePresence(
                  context,
                  () => provider.addCharacterToScene(
                      AdventureCharacterIdentity.effectiveId(character)),
                ),
              )
            : IconButton(
                tooltip: isDead
                    ? l10n.characterManagementDead
                    : l10n.characterManagementUnknown,
                icon: const Icon(Icons.block_outlined),
                onPressed: null,
              )),
```

**改动 4**：删除 `build` 中已被替换掉的 `away` 变量（若 `flutter analyze` 报未使用，直接删）。

### 3.5 [Minor] 清理自引用导入路径

**文件**：同 §3.1，第 4-6 行

将：

```dart
import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../../../../features/adventure/presentation/state/runtime_state_hub_page.dart';
import '../../../../../features/adventure/presentation/state/runtime_state_presentation.dart';
```

改为：

```dart
import '../../../../../application/adventure/adventure_character_identity.dart';
import '../../state/runtime_state_hub_page.dart';
import '../../state/runtime_state_presentation.dart';
```

> 第 4 行是跨 `application/` 层的导入，路径正确，**保持不变**。
> 只有第 5、6 行存在 `features/adventure/.../features/adventure/...` 的自引用回环。

### 3.6 [Minor] 修正两处过时断言

**文件**：`test/widget/custom_attribute_test.dart`

**改动 1**（第 444 行）：把

```dart
      expect(find.text(zh.sceneCharactersTitle), findsOneWidget);
```

改为：

```dart
      // 快捷菜单已收敛：scene_characters 入口被合并进角色管理，
      // 因此这里固化为“不再出现”。
      expect(find.text(zh.sceneCharactersTitle), findsNothing);
```

**改动 2**（第 482 行，位于 `CharacterStatusScreen renders as full-screen Scaffold with tabs`）：
把

```dart
      expect(find.text(zh.characterManagementTitle), findsOneWidget);
```

还原为：

```dart
      expect(find.text(zh.characterStatusTitle), findsOneWidget);
```

> 依据：该 Screen 的 AppBar 是 `title: Text(l10n.characterStatusTitle)`
> （`lib/screens/chat/widgets/character_sheet.dart:1111-1112`，`app_zh.arb:1871` = “角色状态”）。

---

## 4. 测试要求

### 4.1 必须复用的现有工具（不要另造）

- **viewport helper 已存在且必须复用**：`test/helpers/responsive_test_helper.dart`
  导出 `setViewport(tester, width: ..., height: ...)` 和常量 `requiredUiViewports`。
  禁止自己写新的 viewport 辅助函数。
- **现有测试文件已存在**：`test/widget/scene_character_management_page_test.dart`
  已覆盖 6 档 viewport × 3 语言 × `TextScaler 2.0` × 暗色主题。**在此基础上扩充，不要新建文件。**
- Provider 装配模式参考 `test/widget/adventure_session_phase3_test.dart`：
  `UncontrolledProviderScope(container: container, child: MaterialApp(...))`。

### 4.2 必须在 `scene_character_management_page_test.dart` 中新增的测试

**测试 A — 主角分类与按钮**

- 构造一个 `AdventureConfig`，`selectedCharacters` 含一个 `isProtagonist: true` 的行（`characterId: 'card_protagonist'`）
  和一个普通配角行（`characterId: 'card_npc'`）。
- 让权威 `presentCharacterIds` 为 `['protagonist']`。
- 断言：主角名出现在“当前在场”区段内；主角行**不存在** `Icons.login_outlined` 图标。
- 断言：`tester.takeException()` 为 `null`。

**测试 B — 权威投影真实改变（关键，不得只做 `find.text`）**

- 同上配置，点击配角的进入按钮。
- **必须断言的权威读取**：`ScenePresenceMutationResult.state.presentCharacterIds`
  现在包含 `'card_npc'`（即 `addCharacterToScene('card_npc')` 的返回结果里能看到该 id）。
- 或者：重新读取 `provider.sceneParticipantIds` 并断言其包含该 id。
- **不接受**只断言界面上多了一行文字。

**测试 C — 主角不可被加入**

- 断言不存在任何可点击路径对主角调用 `addCharacterToScene`。
- 若实现允许，直接断言 `provider.addCharacterToScene('protagonist')` 的返回 `status`
  为 `SceneMutationStatus.rejected`（依据 `adventure_repository_impl.dart:2152-2156`）。

### 4.3 必须在 `custom_attribute_test.dart` 中验证

- §3.6 两处断言修正后，该文件全部测试通过。

### 4.4 响应式硬门槛（沿用现有 6 档，不得减少）

`320×568`、`360×640`、`390×844`、`412×915`、`768×1024`、`1280×800`，
每档断言 `tester.takeException() == null`，无 `RenderFlex overflow`。
至少一档使用 `TextScaler 2.0`、暗色主题、超长角色名、以及**无运行期实体**
（此时 `_lifeStatus` 为 `null`，应显示“未知”而非崩溃）。

---

## 5. 验证阶梯（按顺序执行，不要跳步，不要先跑全量）

**Step 1 — 静态检查**

```bash
dart format --output=none --set-exit-if-changed .
git diff --check
flutter analyze
```

**Step 2 — 本任务测试**

```bash
flutter test test/widget/scene_character_management_page_test.dart
flutter test test/widget/custom_attribute_test.dart
```

**Step 3 — 相关回归**（用 `rg` 定位，不要靠猜文件名）

```bash
rg -n "RuntimeStateHubPage|SceneCharacterManagementPage" test/
flutter test test/widget/runtime_state_hub_phase4_test.dart
flutter test test/widget/adventure_session_phase3_test.dart
flutter test test/unit/scene_state_structured_evolution_test.dart
```

**Step 4 — 资源库生产流程（只验证，不改）**

```bash
flutter test test/widget/resource_library_production_test.dart -r expanded
```

若失败，必须用只读基线 worktree 对比，**禁止 stash 当前修改**：

```bash
tmpdir=$(mktemp -d)
git worktree add --detach "$tmpdir" HEAD
# 在 $tmpdir 中运行同一测试
# 完成后：git worktree remove "$tmpdir" --force
```

分类：
- **A**：HEAD 处也失败 → 预先存在的基线失败，记录证据，不在本任务修。
- **B**：HEAD 通过、当前工作区失败 → 本任务引入的回归，必须修。
- **C**：不稳定 → 复现三次，取稳定结论。

**Step 5 — 全量**

```bash
flutter test
git diff --check
git status --short
```

---

## 6. 完成判定

**全部满足**才能报告 `READY_FOR_COMMIT`：

1. §3 全部 6 条改动已应用，且未修改 §0.2 列出的任何文件。
2. Step 1–5 全部通过。
3. §4.2 测试 B 的权威投影断言存在且通过。
4. 无既有基线失败；若有，出具 A/B/C 分类证据，并报告
   `BLOCKED_BY_PREEXISTING_BASELINE`，**不得伪报通过**。
5. 工作区保留全部修改，**未创建提交、未推送、未改动远端**。

**报告模板**（必须逐项填写，禁止写“基本完成”“预计完成”“应该没问题”）：

```
完成内容：
根因：
修改文件：
验证命令与结果：
Commit created: NO
Push performed: NO
Remote modified: NO
HEAD SHA:
origin/main SHA:
git status --short：
剩余风险：
```

---

## 7. 当前工作区状态（开工基线）

```
HEAD:        4f5cd16593b000062a941241a54e3b7b34470264
origin/main: 4f5cd16593b000062a941241a54e3b7b34470264
branch:      main
```

已修改文件（18 个，均属有效工作，不得回滚）：

```
 M lib/features/adventure/presentation/session/screens/scene_character_management_page.dart
 M lib/features/adventure/presentation/state/runtime_state_hub_page.dart
 M lib/l10n/app_en.arb
 M lib/l10n/app_ja.arb
 M lib/l10n/app_ko.arb
 M lib/l10n/app_zh.arb
 M lib/l10n/app_zh_Hans.arb
 M lib/l10n/app_zh_Hant.arb
 M lib/l10n/generated/app_localizations.dart
 M lib/l10n/generated/app_localizations_en.dart
 M lib/l10n/generated/app_localizations_ja.dart
 M lib/l10n/generated/app_localizations_ko.dart
 M lib/l10n/generated/app_localizations_zh.dart
 M lib/screens/chat/widgets/quick_menu.dart
 M test/unit/post_removal_smoke_acceptance_test.dart
 M test/widget/adventure_session_phase3_test.dart
 M test/widget/custom_attribute_test.dart
 M test/widget/scene_character_management_page_test.dart
```

---

*报告撰写：claude-opus-5.5*
