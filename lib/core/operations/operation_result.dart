/// 通用操作结果 — 成功/失败判别，供 Controller 方法返回。
///
/// 调用方可通过 [isSuccess]/[isFailure] 分支处理，不再依赖吞掉的
/// `_error` 字段判断成败。
sealed class OperationResult<T> {
  const OperationResult();

  /// 成功结果工厂。
  const factory OperationResult.success(T value) = OperationSuccess<T>;

  /// 失败结果工厂。
  const factory OperationResult.failure(String errorMessage) =
      OperationFailure<T>;

  bool get isSuccess => this is OperationSuccess<T>;
  bool get isFailure => this is OperationFailure<T>;

  /// 成功时的值（失败时为 null）。
  T? get value =>
      this is OperationSuccess<T> ? (this as OperationSuccess<T>).value : null;

  /// 失败时的错误消息（成功时为 null）。
  String? get errorMessage => this is OperationFailure<T>
      ? (this as OperationFailure<T>).errorMessage
      : null;
}

final class OperationSuccess<T> extends OperationResult<T> {
  @override
  final T value;

  const OperationSuccess(this.value);
}

final class OperationFailure<T> extends OperationResult<T> {
  @override
  final String errorMessage;

  const OperationFailure(this.errorMessage);
}
