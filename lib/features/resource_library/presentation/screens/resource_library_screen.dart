import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/refresh/page_refresh_scope.dart';
import 'resource_create_page.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/narr_aitor_library_header.dart';
import '../../../../models/resource_library_mode.dart';
import '../../../../providers/riverpod_providers.dart';
import '../../../resource_studio/presentation/pages/resource_studio_page.dart';
import '../../domain/models/resource_library_view_state.dart';
import '../controllers/resource_library_controller.dart';
import '../widgets/resource_creation_flow.dart';
import '../widgets/resource_trash_sheet.dart';
import 'resource_library_detail_page.dart';

/// Unified library surface. It only supports finding, viewing and creating.
final class ResourceLibraryScreen extends ConsumerStatefulWidget {
  const ResourceLibraryScreen({
    super.key,
    this.initialTab = 0,
    this.onMenuPressed,
    this.onSwitchMode,
    this.mode = ResourceLibraryMode.adventure,
    this.initialResourceId,
  });

  /// Compatibility input for old callers. Values map to the unified filter.
  final int initialTab;
  final VoidCallback? onMenuPressed;
  final VoidCallback? onSwitchMode;
  final ResourceLibraryMode mode;
  final String? initialResourceId;

  @override
  ConsumerState<ResourceLibraryScreen> createState() =>
      _ResourceLibraryScreenState();
}

final class _ResourceLibraryScreenState
    extends ConsumerState<ResourceLibraryScreen> {
  late final ResourceLibraryController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ResourceLibraryController(
      runtime: ref.read(resourceLibraryRuntimeProvider),
      mode: widget.mode,
    );
    final initialFilter = switch (widget.initialTab) {
      1 => ResourceLibraryFilter.character,
      2 => ResourceLibraryFilter.npc,
      _ => ResourceLibraryFilter.all,
    };
    _controller.filter(initialFilter);
    unawaited(_controller.load().then((_) => _openInitialResource()));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageRefreshScope(
      onRefresh: () async {
        await _controller.load();
        return const PageRefreshResult.success();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => _buildContent(context, _controller.state),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ResourceLibraryViewState state,
  ) {
    return Column(
      children: [
        NarrAItorLibraryHeader(
          eyebrow: 'LT',
          title: widget.mode.title,
          onMenuPressed: widget.onMenuPressed,
          onSwitchMode: widget.onSwitchMode,
          actions: [
            IconButton(
              key: const Key('resource-trash-button'),
              tooltip: '回收站',
              onPressed: _showTrash,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
            FilledButton.icon(
              key: const Key('resource-create-button'),
              onPressed: _startCreation,
              icon: const Icon(Icons.add_rounded),
              label: const Text('新建'),
            ),
          ],
          search: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: TextField(
                  key: const Key('resource-search-field'),
                  onChanged: _controller.search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: '搜索资源',
                    isDense: true,
                  ),
                ),
              ),
            ),
          ),
          secondary: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<ResourceLibraryFilter>(
              key: const Key('resource-filter'),
              segments: const [
                ButtonSegment(
                  value: ResourceLibraryFilter.all,
                  label: Text('全部'),
                ),
                ButtonSegment(
                  value: ResourceLibraryFilter.worldview,
                  label: Text('世界观'),
                ),
                ButtonSegment(
                  value: ResourceLibraryFilter.character,
                  label: Text('角色'),
                ),
                ButtonSegment(
                  value: ResourceLibraryFilter.npc,
                  label: Text('NPC'),
                ),
              ],
              selected: <ResourceLibraryFilter>{state.filter},
              onSelectionChanged: (selection) =>
                  _controller.filter(selection.single),
            ),
          ),
        ),
        Expanded(child: _buildBody(context, state)),
      ],
    );
  }

  Widget _buildBody(BuildContext context, ResourceLibraryViewState state) {
    if (state.status == ResourceLibraryStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == ResourceLibraryStatus.error) {
      return _LibraryMessage(
        icon: Icons.error_outline_rounded,
        title: state.errorMessage,
        actionLabel: '重试',
        onAction: _controller.load,
      );
    }
    final items = state.visibleItems;
    if (items.isEmpty) {
      return _LibraryMessage(
        icon: state.query.trim().isEmpty
            ? Icons.folder_open_rounded
            : Icons.search_off_rounded,
        title: state.query.trim().isEmpty ? '还没有资源' : '没有找到匹配的资源',
      );
    }
    return AppRefreshIndicator(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = switch (constraints.maxWidth) {
            >= 900 => 3,
            >= 600 => 2,
            _ => 1,
          };
          final horizontalPadding = constraints.maxWidth < 600 ? 12.0 : 20.0;
          return GridView.builder(
            key: const Key('resource-grid'),
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              12,
              horizontalPadding,
              32,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: 178,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) => _ResourceCard(
              item: items[index],
              onOpen: () => _openDetails(items[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _startCreation() async {
    final availableResources = _controller.state.items
        .where((item) => item.isStudioAvailable)
        .toList(growable: false);

    final draft = await AppRouter.push<Object?>(
      context,
      pageBuilder: (_) => ResourceCreatePage(resources: availableResources),
    );
    if (!mounted || draft == null) return;

    if (draft is ResourceStudioCreationDraft) {
      await AppRouter.push<void>(
        context,
        pageBuilder: (_) => ResourceStudioPage(creationDraft: draft),
      );
      if (mounted) await _controller.load();
    } else if (draft is ManualResourceDraft) {
      final id = await _controller.createManual(
        type: draft.type,
        name: draft.name,
        summary: draft.summary,
      );
      if (!mounted || id == null) return;
      final item = _controller.state.items
          .where((candidate) => candidate.id == id)
          .firstOrNull;
      if (item != null) await _openDetails(item);
    }
  }

  Future<void> _showTrash() async {
    await ResourceTrashSheet.show(
      context,
      ref.read(resourceTrashRuntimeProvider),
    );
    if (mounted) await _controller.load();
  }

  Future<void> _openDetails(ResourceLibraryItem item) async {
    await AppRouter.push<void>(
      context,
      pageBuilder: (_) => ResourceLibraryDetailPage(item: item),
    );
    if (mounted) await _controller.load();
  }

  Future<void> _openInitialResource() async {
    if (!mounted) return;
    final initialId = widget.initialResourceId;
    if (initialId == null || initialId.isEmpty) return;
    final item = _controller.state.items
        .where((candidate) => candidate.id == initialId)
        .firstOrNull;
    if (item != null) await _openDetails(item);
  }
}

final class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.item, required this.onOpen});

  final ResourceLibraryItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey<String>('resource-card-${item.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    item.typeLabel,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  Text(
                    item.status.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.name,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  item.summary.isEmpty ? '暂无简介' : item.summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Align(
                alignment: Alignment.centerRight,
                child: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _LibraryMessage extends StatelessWidget {
  const _LibraryMessage({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 12),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      );
}
