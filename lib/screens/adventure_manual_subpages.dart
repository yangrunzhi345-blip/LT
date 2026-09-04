import 'package:flutter/material.dart';

import '../core/widgets/form_sub_page_scaffold.dart';
import '../core/widgets/narr_aitor_dropdown.dart';

Future<Map<String, String>?> showAdventureManualWorldviewPage(
    BuildContext context) {
  return showFormSubPage<Map<String, String>>(
    context: context,
    title: '手动添加世界观',
    maxWidth: 760,
    builder: (_) => const _WorldviewManualPage(),
  );
}

Future<Map<String, String>?> showAdventureManualCharacterPage(
    BuildContext context) {
  return showFormSubPage<Map<String, String>>(
    context: context,
    title: '手动添加角色卡',
    maxWidth: 840,
    builder: (_) => const _CharacterManualPage(),
  );
}

Future<Map<String, String>?> showAdventureManualNpcPage(BuildContext context) {
  return showFormSubPage<Map<String, String>>(
    context: context,
    title: '手动添加 NPC',
    maxWidth: 760,
    builder: (_) => const _NpcManualPage(),
  );
}

class _WorldviewManualPage extends StatefulWidget {
  const _WorldviewManualPage();

  @override
  State<_WorldviewManualPage> createState() => _WorldviewManualPageState();
}

class _WorldviewManualPageState extends State<_WorldviewManualPage> {
  final _name = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ManualPageLayout(
      title: '世界观信息',
      enabled: _name.text.trim().isNotEmpty,
      onSave: () => Navigator.of(context).pop({
        'name': _name.text.trim(),
        'description': _description.text.trim(),
      }),
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: '名称 *',
            hintText: '例如：中土大陆、赛博都市',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _description,
          minLines: 6,
          maxLines: 12,
          decoration: const InputDecoration(
            labelText: '世界观描述',
            hintText: '世界背景、种族、势力、规则和限制',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

class _CharacterManualPage extends StatefulWidget {
  const _CharacterManualPage();

  @override
  State<_CharacterManualPage> createState() => _CharacterManualPageState();
}

class _CharacterManualPageState extends State<_CharacterManualPage> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _profession = TextEditingController();
  final _personality = TextEditingController();
  final _background = TextEditingController();
  final _appearance = TextEditingController();
  String _gender = '女';

  @override
  void dispose() {
    for (final controller in [
      _name,
      _age,
      _profession,
      _personality,
      _background,
      _appearance,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ManualPageLayout(
      title: '角色卡信息',
      enabled: _name.text.trim().isNotEmpty,
      onSave: () => Navigator.of(context).pop({
        'name': _name.text.trim(),
        'gender': _gender,
        'age': _age.text.trim(),
        'profession': _profession.text.trim(),
        'personality': _personality.text.trim(),
        'background': _background.text.trim(),
        'appearance': _appearance.text.trim(),
      }),
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: '姓名 *',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: NarrAItorDropdown<String>(
                value: _gender,
                label: '性别',
                options: const [
                  NarrAItorDropdownOption(value: '男', label: '男'),
                  NarrAItorDropdownOption(value: '女', label: '女'),
                  NarrAItorDropdownOption(value: '其他', label: '其他'),
                ],
                onChanged: (value) => setState(() => _gender = value ?? '女'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _age,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '年龄',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _field(_profession, '职业 / 身份'),
        const SizedBox(height: 14),
        _field(_personality, '性格', minLines: 2, maxLines: 4),
        const SizedBox(height: 14),
        _field(_background, '背景故事', minLines: 3, maxLines: 6),
        const SizedBox(height: 14),
        _field(_appearance, '外貌描述', minLines: 2, maxLines: 4),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {int minLines = 1, int maxLines = 1}) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

class _NpcManualPage extends StatefulWidget {
  const _NpcManualPage();

  @override
  State<_NpcManualPage> createState() => _NpcManualPageState();
}

class _NpcManualPageState extends State<_NpcManualPage> {
  final _name = TextEditingController();
  final _relation = TextEditingController();
  final _role = TextEditingController();
  final _personality = TextEditingController();
  String _gender = '';

  @override
  void dispose() {
    for (final controller in [_name, _relation, _role, _personality]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ManualPageLayout(
      title: 'NPC 信息',
      enabled: _name.text.trim().isNotEmpty,
      onSave: () => Navigator.of(context).pop({
        'name': _name.text.trim(),
        'relation': _relation.text.trim(),
        'role': _role.text.trim(),
        'gender': _gender,
        'personality': _personality.text.trim(),
      }),
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: '名称 *',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _field(_relation, '关系')),
            const SizedBox(width: 12),
            Expanded(child: _field(_role, '身份')),
          ],
        ),
        const SizedBox(height: 14),
        NarrAItorDropdown<String>(
          value: _gender.isEmpty ? null : _gender,
          label: '性别',
          options: const [
            NarrAItorDropdownOption(value: null, label: '不指定'),
            NarrAItorDropdownOption(value: '男', label: '男'),
            NarrAItorDropdownOption(value: '女', label: '女'),
            NarrAItorDropdownOption(value: '其他', label: '其他'),
          ],
          onChanged: (value) => setState(() => _gender = value ?? ''),
        ),
        const SizedBox(height: 14),
        _field(_personality, '性格 / 描述', minLines: 3, maxLines: 6),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label,
      {int minLines = 1, int maxLines = 1}) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

class _ManualPageLayout extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool enabled;
  final VoidCallback onSave;

  const _ManualPageLayout({
    required this.title,
    required this.children,
    required this.enabled,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('填写完成后保存，返回自由定制父页面继续配置。'),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: enabled ? onSave : null,
                icon: const Icon(Icons.check),
                label: const Text('保存并返回'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
