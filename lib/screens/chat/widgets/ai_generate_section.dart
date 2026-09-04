import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/narr_aitor_dropdown.dart';
import '../../../models/character_card_entry.dart';
import '../../../utils/image_encoder.dart';
import '../../../widgets/narr_aitor_loading.dart';

enum AiGenerateMode { worldview, characterCard }

class AiGenerateSection extends StatefulWidget {
  final AiGenerateMode mode;
  final Future<Map<String, String>> Function(
      {String? prompt,
      String? base64Image,
      String? worldviewHint,
      List<Map<String, String>>? associatedCharacters}) onGenerate;
  final void Function(Map<String, String> result) onFill;
  final Future<void> Function(Map<String, String> result) onSave;
  final bool isVisionModel;
  final String worldviewHint;

  /// 资料库中已有的角色卡条目，供关联角色选择（仅角色卡模式有效）。
  /// 已由 Controller 解析为结构化条目，本组件不再解析 json_data。
  final List<CharacterCardEntry> availableCharacterCards;

  /// 需要从关联选择中排除的角色卡 ID（如当前已选中的主角自身）
  final Set<String>? excludeCardIds;

  /// A scoped flow may fill a temporary card without writing an unassociated
  /// record to the global library.
  final bool canSaveToLibrary;
  final String? saveRestrictionMessage;

  const AiGenerateSection({
    super.key,
    required this.mode,
    required this.onGenerate,
    required this.onFill,
    required this.onSave,
    required this.isVisionModel,
    this.worldviewHint = '',
    this.availableCharacterCards = const [],
    this.excludeCardIds,
    this.canSaveToLibrary = true,
    this.saveRestrictionMessage,
  });

  @override
  State<AiGenerateSection> createState() => _AiGenerateSectionState();
}

class _AiGenerateSectionState extends State<AiGenerateSection> {
  final _textCtrl = TextEditingController();
  final _picker = ImagePicker();
  bool _loading = false;
  bool _expanded = false;
  Map<String, String>? _result;
  String? _error;

  // ─── 关联角色多选状态 ───
  final Set<String> _selectedAssociatedIds = {};

  String get _label => widget.mode == AiGenerateMode.worldview ? '世界观' : '角色卡';

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AiGenerateSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final allowedIds = widget.availableCharacterCards
        .map((card) => card.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    _selectedAssociatedIds.removeWhere((id) => !allowedIds.contains(id));
  }

  // ─── 图片生成 ───

  Future<void> _pickAndGenerate(ImageSource source) async {
    final xfile = await _picker.pickImage(source: source, imageQuality: 85);
    if (xfile == null || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      final base64 = await ImageEncoder.encodeToBase64(xfile.path);

      // 提取选中关联角色的完整字段
      final associatedCharacters = <Map<String, String>>[];
      for (final id in _selectedAssociatedIds) {
        final entry =
            widget.availableCharacterCards.where((e) => e.id == id).firstOrNull;
        if (entry != null) {
          associatedCharacters.add(entry.toAssociatedMap());
        }
      }

      Map<String, String> result;
      result = await widget.onGenerate(
        base64Image: base64,
        worldviewHint: widget.mode == AiGenerateMode.worldview
            ? null
            : widget.worldviewHint,
        associatedCharacters: associatedCharacters,
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = result;
      });
    } on ImageEncodeException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '生成失败: ${e.toString().split('\n').first}';
      });
    }
  }

  // ─── 文字生成 ───

  Future<void> _generateFromText() async {
    final prompt = _textCtrl.text.trim();
    if (prompt.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      // 提取选中关联角色的完整字段
      final associatedCharacters = <Map<String, String>>[];
      for (final id in _selectedAssociatedIds) {
        final entry =
            widget.availableCharacterCards.where((e) => e.id == id).firstOrNull;
        if (entry != null) {
          associatedCharacters.add(entry.toAssociatedMap());
        }
      }

      Map<String, String> result;
      result = await widget.onGenerate(
        prompt: prompt,
        worldviewHint: widget.mode == AiGenerateMode.worldview
            ? null
            : widget.worldviewHint,
        associatedCharacters: associatedCharacters,
      );

      if (!mounted) return;
      setState(() {
        _loading = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '生成失败: ${e.toString().split('\n').first}';
      });
    }
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor =
        isDark ? AppColors.darkSurfaceElevated : AppColors.surfaceElevated;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.accent.withValues(alpha: 0.15);
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── 折叠/展开头部 ──
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.auto_fix_high,
                  size: 16, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                _result != null ? 'AI 已生成$_label' : 'AI 快速生成',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        _result != null ? AppColors.success : AppColors.accent),
              ),
              if (_result != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.check_circle,
                    size: 16, color: AppColors.success),
              ],
              const Spacer(),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: textSecondary),
            ]),
          ),
        ),

        // ── 展开内容 ──
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.isVisionModel) ...[
                Row(children: [
                  _imageBtn('📷 拍照', ImageSource.camera),
                  const SizedBox(width: 8),
                  _imageBtn('🖼 相册', ImageSource.gallery),
                ]),
                const SizedBox(height: 10),
                const Center(
                    child: Text('──── 或输入文字生成 ────',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary))),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _textCtrl,
                minLines: 3,
                maxLines: (MediaQuery.of(context).size.height * 0.4 ~/ 20)
                    .clamp(3, 20),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: widget.mode == AiGenerateMode.worldview
                      ? '描述你想要的场景世界...'
                      : _selectedAssociatedIds.isNotEmpty
                          ? '提示词中写明关联角色的关系'
                          : '描述你想要的角色...',
                  hintStyle: TextStyle(fontSize: 12, color: textSecondary),
                  filled: true,
                  fillColor: isDark ? AppColors.darkSurface : AppColors.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  isDense: true,
                ),
              ),
              // ── 关联已有角色（仅角色卡模式，可折叠可选项） ──
              if (widget.mode == AiGenerateMode.characterCard &&
                  widget.availableCharacterCards.isNotEmpty)
                _buildAssociateCharacterPanel(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _generateFromText,
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('生成$_label', maxLines: 1),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                    child: Column(children: [
                      NarrAItorLoading.mini(),
                      SizedBox(height: 8),
                      Text('AI 正在生成...',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.error))),
                    ]),
                  ),
                ),
              if (_result != null) ...[
                const SizedBox(height: 12),
                _buildResultCard(),
              ],
            ]),
          ),
      ]),
    );
  }

  Widget _imageBtn(String label, ImageSource source) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: _loading ? null : () => _pickAndGenerate(source),
        icon: const Icon(Icons.camera_alt, size: 14),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.accent),
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  /// 关联已有角色（统一多选下拉）。
  Widget _buildAssociateCharacterPanel() {
    final cards = widget.availableCharacterCards
        .where((e) => !(widget.excludeCardIds?.contains(e.id) ?? false))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: NarrAItorMultiSelectDropdown<String>(
        values: _selectedAssociatedIds,
        label: '关联已有角色（可选）',
        emptyText: '暂无已有角色卡',
        selectedBuilder: (values) =>
            values.isEmpty ? '不指定' : '已选 ${values.length} 个角色',
        options: cards.map((entry) {
          return NarrAItorDropdownOption(
            value: entry.id,
            label: entry.name.isEmpty ? '未命名角色' : entry.name,
            subtitle: entry.profession.isEmpty ? null : entry.profession,
          );
        }).toList(),
        onChanged: (values) => setState(() {
          _selectedAssociatedIds
            ..clear()
            ..addAll(values);
        }),
      ),
    );
  }

  Widget _buildResultCard() {
    final r = _result!;
    final isWv = widget.mode == AiGenerateMode.worldview;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(isWv ? '🌍' : '🎭', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(r['name'] ?? '',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textPrimary)),
          ),
          const Text('已生成',
              style: TextStyle(fontSize: 11, color: AppColors.success)),
          const SizedBox(width: 4),
          const Icon(Icons.check_circle, size: 14, color: AppColors.success),
        ]),
        if (!isWv &&
            ((r['gender'] ?? '').isNotEmpty ||
                (r['age'] ?? '').isNotEmpty ||
                (r['profession'] ?? '').isNotEmpty)) ...[
          const SizedBox(height: 4),
          Text(
            [(r['gender'] ?? ''), '${r['age'] ?? ''}岁', (r['profession'] ?? '')]
                .where((s) => s.isNotEmpty)
                .join(' · '),
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          isWv ? (r['description'] ?? '') : (r['background'] ?? ''),
          style: TextStyle(fontSize: 13, height: 1.55, color: textPrimary),
          softWrap: true,
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 4, children: [
          TextButton.icon(
            onPressed: () => setState(() {
              _result = null;
              _error = null;
            }),
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('重新生成', style: TextStyle(fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: widget.canSaveToLibrary ? () => widget.onSave(r) : null,
            icon: const Icon(Icons.save, size: 14),
            label: const Text('保存到资料库', style: TextStyle(fontSize: 12)),
          ),
          FilledButton.icon(
            onPressed: () async {
              // A4: 填入表单时自动存入资源库
              if (widget.canSaveToLibrary) await widget.onSave(r);
              // A1: 填入后自动收起
              widget.onFill(r);
              if (mounted) {
                setState(() {
                  _result = null;
                  _expanded = false;
                });
              }
            },
            icon: const Icon(Icons.edit_note, size: 14),
            label: const Text('填入卡片', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
        ]),
        if (!widget.canSaveToLibrary &&
            widget.saveRestrictionMessage?.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(widget.saveRestrictionMessage!,
              style: TextStyle(fontSize: 11, color: textSecondary)),
        ],
      ]),
    );
  }
}
