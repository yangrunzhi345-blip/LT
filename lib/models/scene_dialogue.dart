import 'dart:convert';

import 'dialogue_level.dart';
import 'adventure_runtime_state.dart';
import 'adventure_config.dart';
import 'game_state.dart';
import 'message.dart';
import 'scene_dialogue_effects.dart';
import 'scene_state.dart';

/// A stable, public identity used by scene features.  Private card fields are
/// deliberately not represented here.
class SceneParticipantRef {
  final String id;
  final String name;
  final String kind;
  final bool isAlive;
  final Map<String, String> publicProfile;

  const SceneParticipantRef({
    required this.id,
    required this.name,
    required this.kind,
    this.isAlive = true,
    this.publicProfile = const {},
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'is_alive': isAlive,
        'public_profile': publicProfile,
      };
}

class ScenePresence {
  final int adventureId;
  final int branchId;
  final String actorId;
  final List<String> participantIds;

  const ScenePresence({
    required this.adventureId,
    required this.branchId,
    required this.actorId,
    required this.participantIds,
  });

  Map<String, dynamic> toRow() => {
        'adventure_id': adventureId,
        'branch_id': branchId,
        'actor_id': actorId,
        'participant_ids_json': jsonEncode(participantIds),
      };
}

class SceneDialogueCommitResult {
  final bool applied;
  final GameState gameState;
  final AdventureConfig? adventureConfig;
  final List<Message> additionalMessages;
  final SceneDialogueEffects effects;
  final SceneState? sceneState;
  final RuntimeHead? runtimeHead;

  const SceneDialogueCommitResult({
    required this.applied,
    required this.gameState,
    required this.effects,
    this.sceneState,
    this.runtimeHead,
    this.adventureConfig,
    this.additionalMessages = const [],
  });
}

/// Immutable input captured before any asynchronous work starts.
class SceneDialogueContextSnapshot {
  final String id;
  final String userInput;
  final Map<String, dynamic> gameState;
  final String currentLocation;
  final SceneParticipantRef actor;
  final List<SceneParticipantRef> presentParticipants;
  final Map<String, dynamic> confirmedWorldview;
  final List<Message> recentMessages;
  final String? summary;
  final List<String> retrievalFacts;
  final List<String> diagnostics;
  final SceneDialogueOutputBudget budget;
  final int runtimeRevision;

  const SceneDialogueContextSnapshot({
    required this.id,
    required this.userInput,
    required this.gameState,
    required this.currentLocation,
    required this.actor,
    required this.presentParticipants,
    required this.confirmedWorldview,
    required this.recentMessages,
    required this.budget,
    this.runtimeRevision = 0,
    this.summary,
    this.retrievalFacts = const [],
    this.diagnostics = const [],
  });
}

class SceneDialogueOutputBudget {
  final int minChineseChars;
  final int targetChineseChars;
  final int maxChineseChars;
  final int recommendedTokens;

  const SceneDialogueOutputBudget(this.minChineseChars, this.targetChineseChars,
      this.maxChineseChars, this.recommendedTokens);

  static const quick = SceneDialogueOutputBudget(500, 750, 1000, 1024);
  static const l0 = SceneDialogueOutputBudget(50, 100, 150, 256);
  static const l1 = SceneDialogueOutputBudget(200, 260, 300, 512);
  static const l2 = SceneDialogueOutputBudget(400, 700, 1000, 1024);
  static const l3 = SceneDialogueOutputBudget(1200, 1600, 2200, 2048);
  static const l4 = SceneDialogueOutputBudget(2500, 3200, 4500, 4096);
  static const l5 = SceneDialogueOutputBudget(4500, 6500, 10000, 8192);

  static SceneDialogueOutputBudget resolve(DialogueLevel level,
      {bool quickMode = false}) {
    if (quickMode && level.id == 'L0') return quick;
    return switch (level.id) {
      'L0' => l0,
      'L1' => l1,
      'L3' => l3,
      'L4' => l4,
      'L5' => l5,
      _ => l2,
    };
  }

  /// 确保高档位下输出容量不被过低的用户设置截断，至少保障当前档位的 recommendedTokens。
  int outputTokensFor(int userMaxTokens) =>
      userMaxTokens > recommendedTokens ? userMaxTokens : recommendedTokens;

  String get promptRequirement =>
      '【第一部分：叙事正文】纯文本至少 $minChineseChars 个中文字（严禁包含后续的 ---JSON---、选项与状态数据！纯叙事正文必须实打实达标）；不设字数上限，根据情节波折自然展开，写足细节后再输出 JSON。';
}

enum SceneSettingCandidateStatus { pending, acceptedAdventure, rejected }

class SceneSettingCandidate {
  static const allowedTypes = {
    'location',
    'faction',
    'rule',
    'custom',
    'timeline',
    'npc'
  };
  static const worldSettingTypes = {
    'location',
    'faction',
    'rule',
    'custom',
    'timeline',
  };
  final String id;
  final String type;
  final String content;
  final String contentHash;

  const SceneSettingCandidate(
      {required this.id,
      required this.type,
      required this.content,
      required this.contentHash});

  bool get isWorldSetting => worldSettingTypes.contains(type);

  String get displayType => switch (type) {
        'location' => '地点',
        'faction' => '势力',
        'rule' => '世界规则',
        'timeline' => '时间线',
        'custom' => '补充设定',
        'npc' => '角色',
        _ => '场景设定',
      };

  static List<SceneSettingCandidate> parse(dynamic value, String requestId) {
    if (value is! List) return const [];
    final seen = <String>{};
    final output = <SceneSettingCandidate>[];
    for (final raw in value) {
      if (raw is! Map) continue;
      final type = raw['type']?.toString().trim().toLowerCase() ?? '';
      final content = raw['content']?.toString().trim() ?? '';
      if (!allowedTypes.contains(type) ||
          content.isEmpty ||
          content.length > 2000) {
        continue;
      }
      final hash =
          base64Url.encode(utf8.encode('$type:$content')).replaceAll('=', '');
      if (!seen.add(hash)) continue;
      output.add(SceneSettingCandidate(
          id: '$requestId-${output.length}',
          type: type,
          content: content,
          contentHash: hash));
    }
    return output;
  }
}
