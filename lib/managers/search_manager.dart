import 'package:flutter/foundation.dart';
import '../models/message.dart';

class SearchManager {
  final VoidCallback notifyParent;

  final List<int> _searchResults = [];
  int _currentSearchIndex = -1;
  String _searchQuery = '';

  List<int> get searchResults => _searchResults;
  int get currentSearchIndex => _currentSearchIndex;
  String get searchQuery => _searchQuery;

  SearchManager({required this.notifyParent});

  void searchMessages(String query, List<Message> messages,
      {Set<String>? bookmarkedIds}) {
    if (_searchQuery == query) {
      _currentSearchIndex = (_currentSearchIndex + 1) % _searchResults.length;
      notifyParent();
      return;
    }
    _searchQuery = query;
    _searchResults.clear();
    _currentSearchIndex = -1;
    if (query.isNotEmpty) {
      for (int i = 0; i < messages.length; i++) {
        if (bookmarkedIds != null && !bookmarkedIds.contains(messages[i].id)) {
          continue;
        }
        if (messages[i].content.toLowerCase().contains(query.toLowerCase())) {
          _searchResults.add(i);
        }
      }
    }
    _currentSearchIndex = _searchResults.isEmpty ? -1 : 0;
    notifyParent();
  }

  void clearSearch() {
    _searchQuery = '';
    _searchResults.clear();
    _currentSearchIndex = -1;
    notifyParent();
  }
}
