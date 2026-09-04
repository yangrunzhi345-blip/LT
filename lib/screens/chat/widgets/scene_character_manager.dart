import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../../models/scene_dialogue.dart';
import '../../../providers/riverpod_providers.dart';

class SceneCharacterManagerScreen extends ConsumerStatefulWidget {
  const SceneCharacterManagerScreen({super.key});

  @override
  ConsumerState<SceneCharacterManagerScreen> createState() =>
      _SceneCharacterManagerScreenState();
}

class _SceneCharacterManagerScreenState
    extends ConsumerState<SceneCharacterManagerScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(chatProvider).refreshSceneCandidates());
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(chatProvider);
    final config = p.adventureConfig;
    if (config == null) return const Scaffold(body: SizedBox.shrink());
    final present = p.sceneParticipantIds.toSet();
    final available = config.supportingCharacters
        .where((c) => c.isAlive && c.name.isNotEmpty)
        .toList();
    final candidates =
        p.pendingSceneCandidates.where((c) => c.type == 'npc').toList();
    final worldCandidates =
        p.pendingSceneCandidates.where((c) => c.isWorldSetting).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('场景设定管理'), actions: [
        IconButton(
            onPressed: p.refreshSceneCandidates,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新候选'),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('在场角色', style: TextStyle(fontWeight: FontWeight.bold)),
        const ListTile(
            leading: Icon(Icons.person),
            title: Text('主角'),
            subtitle: Text('始终在场')),
        for (final character in available.where((c) => present.contains(c.id)))
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(character.name),
            subtitle: Text(character.role.isEmpty ? '配角' : character.role),
            trailing: TextButton(
                onPressed: () => p.removeCharacterFromScene(character.id),
                child: const Text('移出场景')),
          ),
        const Divider(),
        const Text('加入已有角色', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final character in available.where((c) => !present.contains(c.id)))
          ListTile(
            leading: const Icon(Icons.person_add_outlined),
            title: Text(character.name),
            subtitle: Text(character.role.isEmpty ? '配角' : character.role),
            trailing: FilledButton(
                onPressed: () => p.addCharacterToScene(character.id),
                child: const Text('加入')),
          ),
        if (candidates.isNotEmpty) ...[
          const Divider(),
          const Text('AI 提示可添加角色',
              style: TextStyle(fontWeight: FontWeight.bold)),
          for (final candidate in candidates)
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('可添加角色'),
              subtitle: Text(candidate.content,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        SceneNpcApprovalScreen(candidate: candidate))),
                child: const Text('审批'),
              ),
            ),
        ],
        if (worldCandidates.isNotEmpty) ...[
          const Divider(),
          const Text('AI 提示的世界观更新',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('确认后只写入当前冒险的世界设定，并立即用于后续对话。'),
          for (final candidate in worldCandidates)
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text(candidate.displayType),
              subtitle: Text(candidate.content,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        SceneWorldviewApprovalScreen(candidate: candidate))),
                child: const Text('查看'),
              ),
            ),
        ],
      ]),
    );
  }
}

class SceneWorldviewApprovalScreen extends ConsumerStatefulWidget {
  final SceneSettingCandidate candidate;
  const SceneWorldviewApprovalScreen({super.key, required this.candidate});

  @override
  ConsumerState<SceneWorldviewApprovalScreen> createState() =>
      _SceneWorldviewApprovalScreenState();
}

class _SceneWorldviewApprovalScreenState
    extends ConsumerState<SceneWorldviewApprovalScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sceneApprovalControllerProvider);
    final isSubmitting = state.isSubmitting;
    return Scaffold(
        appBar: AppBar(title: Text('确认${widget.candidate.displayType}')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('AI 提出的设定'),
            const SizedBox(height: 8),
            Expanded(
                child: SingleChildScrollView(
                    child: Text(widget.candidate.content))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      final applied = await ref
                          .read(sceneApprovalControllerProvider)
                          .approveWorldCandidate(widget.candidate);
                      if (!mounted) return;
                      if (applied) {
                        navigator.pop();
                      }
                    },
              child: Text(isSubmitting ? '正在确认…' : '确认并用于后续对话'),
            ),
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      await ref
                          .read(sceneApprovalControllerProvider)
                          .rejectCandidate(widget.candidate);
                      if (!mounted) return;
                      navigator.pop();
                    },
              child: const Text('忽略此候选'),
            ),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
              ),
          ]),
        ),
      );
  }
}

class SceneNpcApprovalScreen extends ConsumerStatefulWidget {
  final SceneSettingCandidate candidate;
  const SceneNpcApprovalScreen({super.key, required this.candidate});
  @override
  ConsumerState<SceneNpcApprovalScreen> createState() =>
      _SceneNpcApprovalScreenState();
}

class _SceneNpcApprovalScreenState
    extends ConsumerState<SceneNpcApprovalScreen> {
  late final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sceneApprovalControllerProvider);
    final isSubmitting = state.isSubmitting;
    return Scaffold(
        appBar: AppBar(title: const Text('批准角色加入')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('AI 提出的公开描述'),
            const SizedBox(height: 8),
            Text(widget.candidate.content),
            const SizedBox(height: 24),
            TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: '角色名称', border: OutlineInputBorder())),
            const Spacer(),
            FilledButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (_name.text.trim().isEmpty) return;
                        final navigator = Navigator.of(context);
                        final applied = await ref
                            .read(sceneApprovalControllerProvider)
                            .approveNpc(widget.candidate, name: _name.text);
                        if (!mounted) return;
                        if (applied) {
                          navigator.pop();
                        }
                      },
                child: Text(isSubmitting ? '正在批准…' : '批准并加入当前场景')),
            TextButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        await ref
                            .read(sceneApprovalControllerProvider)
                            .rejectCandidate(widget.candidate);
                        if (!mounted) return;
                        navigator.pop();
                      },
                child: const Text('忽略此候选')),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
              ),
          ]),
        ),
      );
  }
}
