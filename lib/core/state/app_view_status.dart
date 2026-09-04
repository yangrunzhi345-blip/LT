/// 页面数据读取状态。
///
/// [refreshing] 只表示已有内容上的后台读取，页面不应因此清空旧数据。
enum AppViewStatus {
  initial,
  loading,
  refreshing,
  success,
  empty,
  error,
}

extension AppViewStatusX on AppViewStatus {
  bool get isInitialLoad =>
      this == AppViewStatus.initial || this == AppViewStatus.loading;
  bool get hasContent =>
      this == AppViewStatus.success || this == AppViewStatus.refreshing;
  bool get isBusy =>
      this == AppViewStatus.loading || this == AppViewStatus.refreshing;
}
