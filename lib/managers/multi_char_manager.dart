import 'package:flutter/foundation.dart';
import '../models/adventure_config.dart';

class MultiCharManager {
  final VoidCallback notifyParent;

  bool _multiCharacterMode = false;
  List<String> _characterQueue = [];
  int _currentCharacterRound = 0;

  bool get multiCharacterMode => _multiCharacterMode;
  List<String> get characterQueue => _characterQueue;
  int get currentCharacterRound => _currentCharacterRound;

  String? get currentCharacterSpeaker =>
      !_multiCharacterMode || _characterQueue.isEmpty
          ? null
          : _characterQueue[_currentCharacterRound % _characterQueue.length];

  MultiCharManager({required this.notifyParent});

  void toggleMultiCharacterMode(bool enabled,
      {required AdventureConfig? adventureConfig}) {
    _multiCharacterMode = enabled;
    if (enabled && adventureConfig != null) {
      _characterQueue = [
        adventureConfig.name,
        ...adventureConfig.supportingCharacters.map((c) => c.name)
      ].where((n) => n.isNotEmpty).toList();
      _currentCharacterRound = 0;
    }
    notifyParent();
  }

  void advanceCharacterRound() {
    if (!_multiCharacterMode) return;
    _currentCharacterRound++;
    notifyParent();
  }

  String buildMultiCharacterPrompt() {
    if (!_multiCharacterMode || _characterQueue.isEmpty) return '';
    return '当前发言角色：$currentCharacterSpeaker\n参与角色：${_characterQueue.join('、')}\n请仅以当前发言角色的视角回复。';
  }
}
