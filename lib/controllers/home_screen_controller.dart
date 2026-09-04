import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/adventure_config.dart';
import '../utils/ai_adventure_utils.dart';

/// 冒险向导静态壳 — 选项常量与静态草稿读取。
///
/// 实例业务（表单状态、AI 生成、模板读写、草稿写入）已拆分至
/// [AdventureDraftController]（见 adventure_draft_controller.dart）。
/// 本类保留 landing 等页面使用的静态选项与静态草稿读取入口。
class HomeScreenController {
  static const worldviewOptions = [
    '奇幻大陆',
    '科幻星河',
    '现代都市',
    '古代江湖',
    '末日废土',
    '仙侠修真',
    '赛博朋克',
    '克苏鲁神话',
  ];
  static const nameOptions = ['星辰', '夜澜', '青云', '墨羽'];
  static const genderOptions = ['男', '女', '非二元'];
  static const ageOptions = [
    '少年 (12-17)',
    '青年 (18-25)',
    '成年 (26-35)',
    '中年 (36-50)',
    '老年 (50+)'
  ];
  static const heightOptions = ['娇小', '中等', '高挑', '极高'];
  static const heightOptionsMale = ['中等', '高挑', '极高'];
  static const skinToneOptions = ['白皙', '小麦色', '古铜色', '深色'];
  static const facialFeaturesOptions = ['精致', '深邃', '柔和', '英气'];
  static const hairStyleOptions = ['长发', '短发', '卷发', '盘发'];
  static const hairColorOptions = ['黑色', '金色', '银色', '红色'];
  static const personalityOptions = [
    '开朗活泼，热情洋溢，总能带动周围气氛',
    '沉稳内敛，深思熟虑，行事不疾不徐',
    '冷酷寡言，外表淡漠却内心细腻敏感',
    '温柔体贴，善解人意，如春风拂面般温暖',
    '叛逆不羁，崇尚自由，不拘世俗礼法约束',
    '机智狡黠，反应敏捷，善于随机应变周旋',
    '正直刚毅，光明磊落，坚守原则毫不退缩',
    '天真烂漫，纯洁无邪，对世界充满无限好奇',
    '热血冲动，充满激情与干劲，行动力极强',
    '洒脱豁达，看淡得失荣辱，心境超然物外',
  ];
  static const narrativePersonOptions = ['第一人称（我）', '第二人称（你）', '第三人称（TA）'];
  static const styleEnhancementOptions = ['简洁直白', '华丽修辞', '幽默风趣', '诗意盎然'];
  static const protagonistClassOptions = [
    '战士',
    '法师',
    '游侠',
    '盗贼',
    '牧师',
    '圣骑士',
    '术士',
    '猎人',
    '武僧',
    '吟游诗人'
  ];
  static const protagonistBgOptions = [
    '流浪孤儿',
    '贵族后裔',
    '学院弟子',
    '隐世高人',
    '退伍军人',
    '商贾之家',
    '乡村少年',
    '沙漠旅者',
    '宫廷密探',
    '自由佣兵'
  ];
  static const relationOptions = [
    '挚友',
    '导师',
    '恋人',
    '宿敌',
    '盟友',
    '仆从',
    '兄弟/姐妹',
    '青梅竹马',
    '冒险同伴'
  ];
  static const roleOptions = [
    '男主',
    '女主',
    '男二',
    '女二',
    '反派',
    '盟友',
    '导师',
    '神秘人',
    'NPC'
  ];
  static const presetScenes = [
    '奇幻森林 —— 你醒来时发现自己身处一片幽暗的密林，树木遮天蔽日，远处传来不明生物的嗥叫...',
    '末日废土 —— 核爆后的第十年，你从地下掩体中走出，眼前是一片荒芜的废墟和枯黄的大地...',
    '古堡迷踪 —— 一封神秘信件将你引至这座被遗忘的古堡，推开沉重的大门，尘封的秘密即将揭晓...',
    '太空漂泊 —— 宇宙飞船的警报声划破了寂静，你从冬眠舱中苏醒，舷窗外是陌生的星域...',
    '深海秘境 —— 潜水器缓缓下沉，探照灯照亮了一个从未被发现的深海洞穴...',
    '江湖风起 —— 茶馆外马蹄声碎，你紧握怀中的神秘令牌，未知的江湖恩怨正向你逼近...',
    '赛博都市 —— 霓虹灯下，你是一名街头黑客，刚截获一条加密信息...',
    '虚空幻境 —— 传送阵的光芒消散，你发现自己身处一个由魔法编织的异世界...',
  ];

  static Future<List<Map<String, dynamic>>> loadAllDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = <Map<String, dynamic>>[];
    const maxSlots = 10;
    for (int i = 0; i < maxSlots; i++) {
      final raw = prefs.getString('draft_$i');
      if (raw != null) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final config = AdventureConfig.fromJson(json);
          final t = prefs.getInt('draft_${i}_ts') ?? 0;
          if (config.name.isNotEmpty || config.worldview.isNotEmpty) {
            drafts.add({
              'slot': i,
              'name': config.name.isNotEmpty
                  ? config.name
                  : (config.worldview.isNotEmpty ? config.worldview : '未命名'),
              'worldview': config.worldview,
              'ts': t,
              'config': config,
            });
          }
        } catch (_) {}
      }
    }
    drafts.sort((a, b) => (b['ts'] as int).compareTo(a['ts'] as int));
    return drafts;
  }

  static Future<AdventureConfig?> loadLatestDraft() async {
    final prefs = await SharedPreferences.getInstance();
    AdventureConfig? latest;
    int latestTime = 0;
    const maxSlots = 10;
    for (int i = 0; i < maxSlots; i++) {
      final raw = prefs.getString('draft_$i');
      if (raw != null) {
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          final config = AdventureConfig.fromJson(json);
          if (config.name.isNotEmpty || config.worldview.isNotEmpty) {
            final t = prefs.getInt('draft_${i}_ts') ?? 0;
            if (t > latestTime) {
              latestTime = t;
              latest = config;
            }
          }
        } catch (_) {}
      }
    }
    return latest;
  }

  static String? checkWorldviewCompatibility(
      String worldviewName, String profession) {
    if (worldviewName.contains('修仙') && profession.contains('机械师')) {
      return '机械师与修仙世界观不太匹配';
    }
    if (worldviewName.contains('赛博') && profession.contains('骑士')) {
      return '骑士与赛博世界观不太匹配';
    }
    return null;
  }

  static Map<String, dynamic>? parseAiJson(String text) {
    return AiAdventureUtils.parseJson(text);
  }
}
