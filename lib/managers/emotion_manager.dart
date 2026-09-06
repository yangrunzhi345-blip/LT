import 'package:flutter/foundation.dart';

class EmotionManager {
  final VoidCallback notifyParent;

  String _lastEmotion = '';

  String get lastEmotion => _lastEmotion;

  static final Map<String, RegExp> _emotionPatterns = {
    '愉快': RegExp(r'(开心|高兴|愉快|兴奋|欣喜)'),
    '悲伤': RegExp(r'(悲伤|难过|哭泣|伤心|悲痛)'),
    '愤怒': RegExp(r'(愤怒|生气|恼怒|暴怒|怒火)'),
    '恐惧': RegExp(r'(害怕|恐惧|惊恐|畏惧|颤抖)'),
    '惊讶': RegExp(r'(惊讶|震惊|意外|吃惊|不可思议)'),
    '思考': RegExp(r'(思索|思考|沉思|困惑|不解)'),
    '平静': RegExp(r'(平静|冷静|安宁|祥和|淡淡)'),
  };

  static const Map<String, String> _emotionEmojis = {
    '愉快': '😄',
    '悲伤': '😢',
    '愤怒': '😠',
    '恐惧': '😨',
    '惊讶': '😲',
    '思考': '🤔',
    '平静': '😌',
  };

  EmotionManager({required this.notifyParent});

  String detectEmotion(String text) {
    for (final e in _emotionPatterns.entries) {
      if (e.value.hasMatch(text)) {
        _lastEmotion = e.key;
        final emoji = _emotionEmojis[e.key] ?? '😊';
        return '$emoji ${e.key}';
      }
    }
    _lastEmotion = '';
    return '';
  }
}
