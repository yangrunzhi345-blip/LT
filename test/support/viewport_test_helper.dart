import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 统一的测试 Viewport 辅助工具
///
/// 覆盖从最低兼容尺寸 (320px) 到宽屏桌面 (1440px) 的关键视口
class TestViewports {
  TestViewports._();

  /// 最低兼容逻辑尺寸 (AGENTS.md 硬性约束门槛)
  static const Size mobile320 = Size(320, 568);

  /// 常见小屏 Android 设备
  static const Size mobile360 = Size(360, 640);

  /// 标准主流 iPhone 设备
  static const Size mobile390 = Size(390, 844);

  /// 较宽大屏移动设备
  static const Size mobile412 = Size(412, 915);

  /// 移动端横屏场景
  static const Size landscapeMobile = Size(844, 390);

  /// 平板 / Compact Desktop
  static const Size tablet768 = Size(768, 1024);

  /// 常见桌面视口
  static const Size desktop1024 = Size(1024, 768);

  /// 宽屏桌面工作区
  static const Size desktop1440 = Size(1440, 900);
}

/// 设置测试环境的物理视口并自动在测试结束时恢复
void setTestViewport(
  WidgetTester tester, {
  required Size size,
  double devicePixelRatio = 1.0,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = devicePixelRatio;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
