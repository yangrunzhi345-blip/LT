/// NarrAItor 尺寸与维度令牌系统
///
/// 集中定义通用控件高度、页面最大内容宽度与硬门槛约束，
/// 杜绝代码中散落未经解释的尺寸魔法值。
class AppDimensions {
  AppDimensions._();

  // ─── 统一控件高度令牌 (Control Heights) ───
  /// 小尺寸控件高度（如 Compact 按钮、紧凑 Chip/Dropdown）
  static const double controlHeightSm = 32.0;

  /// 标准中尺寸控件高度（如普通操作按钮、标准输入框、列表项操作区）
  static const double controlHeightMd = 40.0;

  /// 大尺寸控件高度（如主表单输入框、底部常驻主要保存按钮）
  static const double controlHeightLg = 48.0;

  // ─── 页面与容器最大宽度令牌 (Content Max Widths) ───
  /// 统一子页面/表单默认最大内容宽度（FormSubPageScaffold / AppPageScaffold）
  static const double maxContentWidth = 840.0;

  /// 单列舒适表单与设置项最大宽度
  static const double maxFormWidth = 640.0;

  /// 叙事与小说阅读舒适正文最大宽度 (35–45 个汉字字符)
  static const double maxNarrativeWidth = 760.0;

  /// 资料库网格与卡片画廊最大宽度
  static const double maxGalleryWidth = 1200.0;

  // ─── 最低兼容逻辑宽度（硬门槛） ───
  /// AGENTS.md 规定的最低兼容逻辑宽度，绝不允许出现横向 RenderFlex Overflow
  static const double minSupportedWidth = 320.0;
}
