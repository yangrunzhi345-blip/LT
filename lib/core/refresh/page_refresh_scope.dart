import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;

import '../../providers/riverpod_providers.dart';
import '../feedback/app_feedback.dart';
import 'page_refresh_controller.dart';

export 'page_refresh_controller.dart';

/// 将当前可见页面的刷新回调注册给应用级刷新入口。
class PageRefreshScope extends ConsumerStatefulWidget {
  const PageRefreshScope({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final PageRefreshCallback onRefresh;
  final Widget child;

  @override
  ConsumerState<PageRefreshScope> createState() => _PageRefreshScopeState();
}

class _PageRefreshScopeState extends ConsumerState<PageRefreshScope> {
  final Object _owner = Object();
  late final PageRefreshController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(pageRefreshControllerProvider);
    _register();
  }

  void _register() {
    _controller.register(_owner, widget.onRefresh);
  }

  @override
  void dispose() {
    _controller.unregister(_owner);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 为滚动页面提供统一的移动端下拉刷新入口。
class AppRefreshIndicator extends ConsumerWidget {
  const AppRefreshIndicator({
    super.key,
    required this.child,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final Widget child;
  final ScrollNotificationPredicate notificationPredicate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator.adaptive(
      notificationPredicate: notificationPredicate,
      onRefresh: () async {
        final result = await ref.read(pageRefreshControllerProvider).refresh();
        if (!result.isSuccess && context.mounted) {
          AppFeedback.error(context, result.error ?? '刷新失败，请稍后重试');
        }
      },
      child: child,
    );
  }
}
