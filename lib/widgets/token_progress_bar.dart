import 'package:flutter/material.dart';

const tokenThreshold = 1000000;

Color tokenBarColor(double ratio) {
  // 渐变锚点: 0%绿 → 30%蓝 → 40%青绿 → 50%橙 → 60%橙红 → 70%鲜红 → 80%深红 → 90%黑
  const anchors = [
    (0.0, Color(0xFF4CAF50)), // 绿色
    (0.3, Color(0xFF2196F3)), // 蓝色
    (0.4, Color(0xFF00BCD4)), // 青绿色
    (0.5, Color(0xFFFF9800)), // 橙色
    (0.6, Color(0xFFFF5722)), // 橙红色
    (0.7, Color(0xFFF44336)), // 鲜红色
    (0.8, Color(0xFFD32F2F)), // 深红色
    (0.9, Color(0xFF000000)), // 黑色
  ];
  if (ratio <= 0.0) return anchors.first.$2;
  if (ratio >= 0.9) return anchors.last.$2;
  // 在相邻锚点间线性插值
  for (int i = 0; i < anchors.length - 1; i++) {
    if (ratio >= anchors[i].$1 && ratio <= anchors[i + 1].$1) {
      final t = (ratio - anchors[i].$1) / (anchors[i + 1].$1 - anchors[i].$1);
      return Color.lerp(anchors[i].$2, anchors[i + 1].$2, t)!;
    }
  }
  return anchors.first.$2;
}
