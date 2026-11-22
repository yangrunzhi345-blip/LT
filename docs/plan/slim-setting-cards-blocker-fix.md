# Slim Setting Cards — BLOCKER（B1–B4）修复实施规格

- 基线：`refactor/slim-setting-cards` @ `eba5124`
- 范围：仅修复 B1–B4；不恢复关系写入、revision、NPC 批量、Wizard 选中回填、英文标题中文化
- 验收模式：Integrated Single-Agent Full-Cycle（用户明确授权主 Agent 集成 + 独立只读 Review 子 Agent）

## 目标

1. **B1 生成输入脱钩**：`SettingCardService.generate` 透传 `worldview` / `associatedCharacters` / `targetTotalCharacters` / `reference`，并在 `originWorldviewId` 存在时自动加载世界观卡。
2. **B2 角色/NPC 快照丢字段**：冻结时按 Markdown/JSON 还原完整角色字段，主角不再清空 `personality` / `characterCard`，并把 `custom_attributes` / `tracked_state_definitions` 传播到 `supportingCharacters`，使追踪定义可派生。
3. **B3 世界观模块归零**：冻结时按三级优先级还原 `detail_json` 模块，非 archived 模块归一化为 confirmed（仅快照副本），并通过 `WorldviewSnapshotService.snapshot` / `buildManagedEntries` 生成托管条目。
4. **B4 参考材料入口消失**：新增参考源模型与上下文预算器，创建/详情页支持粘贴、导入文件（文件名+内容双输入）、引用已有卡，并透传到生成。

## 锁定的新增公开签名

### `lib/application/setting_cards/setting_card_markdown_parser.dart`

```dart
final class SettingCardMarkdownParser {
  const SettingCardMarkdownParser();

  static const String structuredPayloadKey = 'structured_payload';
  static const String detailJsonKey = 'detail_json';

  /// 解析 `## <key>` 段落；```json 代码块解码为 Map/List；
  /// 无标题时尝试整份 JSON（兼容 LegacyCardMirror）。
  /// 纯文本/空内容返回 `{'description': content}` 或空 Map，绝不抛异常。
  Map<String, dynamic> parseSections(String content);

  /// 合并优先级：content 段落 > metadata['structured_payload'] > name/summary/content 兜底。
  Map<String, dynamic> resolveStructuredPayload(SettingCard card);

  /// 世界观 detail：content `## detail` / `## <moduleKey>` > metadata['detail_json'] > WorldviewDetails.simple。
  /// 返回 `{format_version, mode, modules}`，非 archived 模块归一化为 confirmed（不修改原卡）。
  Map<String, dynamic> resolveWorldviewDetail(SettingCard card);
}
```

### `lib/application/setting_cards/setting_card_reference_input.dart`

```dart
enum SettingCardReferenceMode { paste, file, existingCard }

final class SettingCardReferenceInput {
  const SettingCardReferenceInput({
    required this.mode,
    this.label = '',
    this.text = '',
    this.sourceCardId = '',
  });

  final SettingCardReferenceMode mode;
  final String label;
  final String text;
  final String sourceCardId;

  bool get isEmpty;
}
```

### `lib/application/setting_cards/setting_card_context_budgeter.dart`

```dart
final class SettingCardContextBudgeter {
  const SettingCardContextBudgeter();

  static const int maximumReferenceCharacters = 8000;
  static const int maximumWorldviewCharacters = 8000;
  static const int maximumModuleCharacters = 1600;
  static const int maximumPersonalityCharacters = 280;
  static const int maximumBackgroundCharacters = 400;

  String selectReference({required String source, required String reference});
  String selectWorldview({required String source, required String worldview});
  List<Map<String, String>> summarizeAssociatedCharacters(
    List<Map<String, String>> characters,
  );
}
```

### `SettingCardService.generate`（扩展后）

```dart
Future<SettingCard> generate({
  required String id,
  required String instruction,
  String worldview = '',
  List<Map<String, String>> associatedCharacters = const [],
  int? targetTotalCharacters,
  SettingCardReferenceInput? reference,
  void Function(int currentStage, int totalStages, String stageName)? onProgress,
});
```

- `existingCard` 引用的卡不存在时抛 `SettingCardGenerationException`（信息含 id）。
- 角色/NPC：`worldview` 为空且 `card.originWorldviewId` 非空时自动加载该世界观卡正文。
- 参考材料与世界观均经 `SettingCardContextBudgeter` 裁剪后拼入 `source`（gateway 无独立 ref 参数）。
- 生成成功后写 metadata：世界观 `detail_json`，角色/NPC `structured_payload`（保留既有 metadata 键）。

## 文件边界

| Owner | 文件 |
| --- | --- |
| Agent A | `setting_card_markdown_parser.dart`（新）、`setting_card_adventure_snapshot.dart`、对应测试 |
| Agent B | `setting_card_reference_input.dart`（新）、`setting_card_context_budgeter.dart`（新）、对应测试 |
| 主 Agent | `setting_card_service.dart`、`test/helpers/setting_card_fakes.dart` |
| Agent C | `adventure_wizard_ai_drafts.dart`、service 单测 |
| Agent D | `setting_card_create_page.dart`、`setting_card_detail_page.dart`、`app_zh.arb`/`app_en.arb`、Widget 测试 |

## 测试要求

- Parser：纯文本、JSON 段落、content>metadata 优先级、空 metadata、世界观三级回退、archived 保留。
- Snapshot：`freeze` monitor > 0；`buildOpeningCanonContext` 提取 faction/home_location；`buildManagedEntries` 多条；主角 personality 不清空。
- Budgeter：8000 上限、单模块 1600、性格 280 / 背景 400、相关度优先。
- Service：参数透传、originWorldviewId 自动加载、existingCard 缺失抛错、metadata 写入。
- Widget：三档参考切换、字数提示、透传。
- 回归：`adventure_assembler_relationship_test.dart`、`opening_canon_context_test.dart`、`adventure_setup_controller_concurrency_test.dart`、全部 `setting_cards` 测试。
- `flutter analyze` 0 error / 0 warning；`git diff --check` 干净。

## 禁止

- 修改 `pubspec.yaml` 或引入依赖；回退单表架构；破坏性 Git；push；跳过/放宽测试；mock 真实解析路径。
