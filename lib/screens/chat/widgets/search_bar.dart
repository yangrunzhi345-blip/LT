import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider;
import '../../../core/theme/app_colors.dart';
import '../../../providers/riverpod_providers.dart';

class ChatSearchBar extends StatefulWidget {
  final VoidCallback onClose;

  const ChatSearchBar({
    super.key,
    required this.onClose,
  });

  @override
  State<ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends State<ChatSearchBar> {
  bool _bookmarksOnly = false;

  void _search(WidgetRef ref, String q) {
    final p = ref.read(chatProvider);
    ref.read(messagingProvider).searchMessages(
          q,
          p.messages,
          bookmarkedIds: _bookmarksOnly ? p.bookmarkedMessageIds.toSet() : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer(
      builder: (_, ref, __) {
        final p = ref.watch(chatProvider);
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          color: isDark ? AppColors.darkSurface : AppColors.background,
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: p.searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜索对话内容...',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilterChip(
                        label: const Text('仅书签'),
                        labelStyle: const TextStyle(fontSize: 10),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        selected: _bookmarksOnly,
                        onSelected: (value) {
                          setState(() => _bookmarksOnly = value);
                          _search(ref, p.searchQuery);
                        },
                      ),
                      const SizedBox(width: 4),
                      Text(
                          '${p.searchResults.isEmpty ? 0 : p.currentSearchIndex + 1}/${p.searchResults.length}',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                        onPressed: p.searchResults.isEmpty
                            ? null
                            : () => _search(ref, p.searchQuery),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                        onPressed: p.searchResults.isEmpty
                            ? null
                            : () {
                                final q = p.searchQuery;
                                p.clearSearch();
                                _search(ref, q);
                              },
                      ),
                    ],
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (q) => _search(ref, q),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                p.clearSearch();
                widget.onClose();
              },
            ),
          ]),
        );
      },
    );
  }
}
