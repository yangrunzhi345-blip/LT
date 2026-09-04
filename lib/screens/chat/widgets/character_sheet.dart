import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../widgets/sheet_handle.dart';

/// 角色卡 BottomSheet — 点击角色头像后弹出
void showCharacterSheet({
  required BuildContext context,
  required String name,
  required String role,
  required int hp,
  required int maxHp,
  required int energy,
  required int maxEnergy,
  required int gold,
  required bool isDark,
  // v2.0 params
  int level = 1,
  int mp = 0,
  int maxMp = 0,
  int skillPoints = 0,
  int baseAtk = 5,
  int baseDef = 3,
  int baseSpeed = 5,
  int experience = 0,
  // v2.13: 结构化背包
  String? characterId,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (ctx, scrollCtrl) => _CharacterSheetContent(
        scrollCtrl: scrollCtrl,
        name: name,
        role: role,
        hp: hp,
        maxHp: maxHp,
        energy: energy,
        maxEnergy: maxEnergy,
        gold: gold,
        isDark: isDark,
        level: level,
        mp: mp,
        maxMp: maxMp,
        skillPoints: skillPoints,
        baseAtk: baseAtk,
        baseDef: baseDef,
        baseSpeed: baseSpeed,
        experience: experience,
        characterId: characterId,
      ),
    ),
  );
}

class _CharacterSheetContent extends ConsumerStatefulWidget {
  final ScrollController scrollCtrl;
  final String name, role;
  final int hp, maxHp, energy, maxEnergy, gold;
  final bool isDark;
  final int level, mp, maxMp, skillPoints;
  final int baseAtk, baseDef, baseSpeed, experience;
  final String? characterId;

  const _CharacterSheetContent({
    required this.scrollCtrl,
    required this.name,
    required this.role,
    required this.hp,
    required this.maxHp,
    required this.energy,
    required this.maxEnergy,
    required this.gold,
    required this.isDark,
    this.level = 1,
    this.mp = 0,
    this.maxMp = 0,
    this.skillPoints = 0,
    this.baseAtk = 5,
    this.baseDef = 3,
    this.baseSpeed = 5,
    this.experience = 0,
    this.characterId,
  });

  @override
  ConsumerState<_CharacterSheetContent> createState() =>
      _CharacterSheetContentState();
}

class _CharacterSheetContentState extends ConsumerState<_CharacterSheetContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    final isDark = widget.isDark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.grey;

    return ListView(
      controller: widget.scrollCtrl,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        const SheetHandle(),
        const SizedBox(height: 16),
        // Header: name + role
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.avatarColors[0],
            child: Text(widget.name.isNotEmpty ? widget.name[0] : '?',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.name,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: textColor)),
            Text(widget.role, style: TextStyle(fontSize: 13, color: subColor)),
          ]),
        ]),
        const SizedBox(height: 16),

        // Status cards
        Row(children: [
          _StatusCard(
              icon: '❤️',
              label: 'HP',
              value: widget.hp,
              max: widget.maxHp,
              color: Colors.red,
              isDark: isDark),
          const SizedBox(width: 8),
          _StatusCard(
              icon: '⚡',
              label: '能量',
              value: widget.energy,
              max: widget.maxEnergy,
              color: Colors.blue,
              isDark: isDark),
          const SizedBox(width: 8),
          _StatusCard(
              icon: '💰',
              label: '金币',
              value: widget.gold,
              max: null,
              color: Colors.amber,
              isDark: isDark),
        ]),
        const SizedBox(height: 16),

        // Tabs
        TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.accent,
          unselectedLabelColor: subColor,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: '背包'),
            Tab(text: '属性'),
            Tab(text: '技能'),
          ],
        ),
        SizedBox(
          height: 200,
          child: TabBarView(controller: _tabCtrl, children: [
            _buildInventoryTab(isDark),
            _buildStatsTab(isDark),
            _buildSkillsTab(isDark),
          ]),
        ),
      ],
    );
  }

  Widget _buildInventoryTab(bool isDark) {
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final subColor = isDark ? Colors.white38 : Colors.grey;
    final controller = ref.read(adventureGameControllerProvider);

    // v2.13: 结构化背包视图（经 AdventureGameController 读取）
    {
      final charId = widget.characterId;
      final equipment = controller.equipmentFor(charId);
      final charItems = controller.itemsFor(charId);
      // 公共物品（不属于任何角色）
      final sharedItems = controller.itemsFor(null);

      if (equipment.isEmpty && charItems.isEmpty && sharedItems.isEmpty) {
        return Center(
          child: Text('背包空空如也',
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        );
      }

      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          // 已装备区
          if (equipment.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text('⚔️ 已装备',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent)),
            ),
            ...equipment.map((eq) => ListTile(
                  dense: true,
                  leading: Text(eq.icon.isNotEmpty ? eq.icon : '⚔️',
                      style: const TextStyle(fontSize: 16)),
                  title: Text(eq.name,
                      style: TextStyle(fontSize: 13, color: textColor)),
                  subtitle: Text('${eq.slot.name} · ${eq.quality.name}',
                      style: TextStyle(fontSize: 10, color: subColor)),
                )),
            const Divider(height: 16),
          ],
          // 角色专属物品
          if (charItems.isNotEmpty && charId != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('🎒 ${widget.name}的背包',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent)),
            ),
            ...charItems.map((item) => ListTile(
                  dense: true,
                  leading:
                      Text(item.icon, style: const TextStyle(fontSize: 16)),
                  title: Text(item.name,
                      style: TextStyle(fontSize: 13, color: textColor)),
                  trailing: item.quantity > 1
                      ? Text('×${item.quantity}',
                          style: TextStyle(fontSize: 12, color: subColor))
                      : null,
                )),
          ],
          // 公共物品
          if (sharedItems.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Text('📦 公共物品',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: subColor)),
            ),
            ...sharedItems.map((item) => ListTile(
                  dense: true,
                  leading:
                      Text(item.icon, style: const TextStyle(fontSize: 16)),
                  title: Text(item.name,
                      style: TextStyle(fontSize: 13, color: textColor)),
                  trailing: item.quantity > 1
                      ? Text('×${item.quantity}',
                          style: TextStyle(fontSize: 12, color: subColor))
                      : null,
                )),
          ],
        ],
      );
    }
  }

  Widget _buildStatsTab(bool isDark) {
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final hpPct =
        widget.maxHp > 0 ? (widget.hp / widget.maxHp * 100).round() : 100;
    final enPct = widget.maxEnergy > 0
        ? (widget.energy / widget.maxEnergy * 100).round()
        : 100;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        _StatRow(
            '❤️ HP', widget.hp, widget.maxHp, hpPct, Colors.red, textColor),
        const SizedBox(height: 8),
        _StatRow('⚡ 能量', widget.energy, widget.maxEnergy, enPct, Colors.blue,
            textColor),
        const SizedBox(height: 8),
        Row(children: [
          Text('💰 金币', style: TextStyle(fontSize: 13, color: textColor)),
          const Spacer(),
          Text('${widget.gold}',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
        ]),
      ]),
    );
  }

  Widget _buildSkillsTab(bool isDark) {
    final subColor = isDark ? Colors.white38 : Colors.grey;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // v2.0 Status row
        Row(children: [
          _MiniStat(label: 'Lv', value: '${widget.level}'),
          const SizedBox(width: 12),
          _MiniStat(label: 'MP', value: '${widget.mp}/${widget.maxMp}'),
          const SizedBox(width: 12),
          _MiniStat(label: 'EXP', value: '${widget.experience}'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _MiniStat(label: 'ATK', value: '${widget.baseAtk}'),
          const SizedBox(width: 12),
          _MiniStat(label: 'DEF', value: '${widget.baseDef}'),
          const SizedBox(width: 12),
          _MiniStat(label: 'SPD', value: '${widget.baseSpeed}'),
        ]),
        const SizedBox(height: 8),
        Text('🔧 技能点: ${widget.skillPoints}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.accent)),
        const SizedBox(height: 12),
        Divider(color: Colors.grey[300]),
        const SizedBox(height: 8),
        Text('💡 提示：在聊天中使用快捷菜单(📋)',
            style: TextStyle(fontSize: 11, color: subColor)),
        Text('可查看技能列表、任务、地图', style: TextStyle(fontSize: 11, color: subColor)),
      ]),
    );
  }
}

// ─── 子组件 ───

class _StatusCard extends StatelessWidget {
  final String icon, label;
  final int value;
  final int? max;
  final Color color;
  final bool isDark;

  const _StatusCard(
      {required this.icon,
      required this.label,
      required this.value,
      this.max,
      required this.color,
      required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ratio =
        max != null && max! > 0 ? (value / max!).clamp(0.0, 1.0) : 1.0;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(icon, style: const TextStyle(fontSize: 22)),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white54 : Colors.grey)),
            Text('$value${max != null ? '/$max' : ''}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87)),
            if (max != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 10,
                  backgroundColor: color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            else
              const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final int value, max, pct;
  final Color color;
  final Color textColor;

  const _StatRow(
      this.label, this.value, this.max, this.pct, this.color, this.textColor);

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: TextStyle(fontSize: 13, color: textColor)),
        const Spacer(),
        Text('$value/$max  $pct%',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: textColor)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: LinearProgressIndicator(
          value: value / max,
          minHeight: 10,
          backgroundColor: color.withValues(alpha: 0.12),
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      ),
    ]);
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: TextStyle(
              fontSize: 9,
              color: Colors.grey[500],
              fontWeight: FontWeight.w600)),
      Text(value,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.accent)),
    ]);
  }
}
