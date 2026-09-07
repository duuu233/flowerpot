class ApiException implements Exception {
  const ApiException(
    this.code,
    this.message, {
    this.data,
    this.body,
    bool? authError,
  }) : _authError = authError;

  final Object code;
  final String message;
  final Object? data;

  /// 后端返回的原始响应体（凭证字段已打码，超长会截断）。
  ///
  /// 只在开发构建里填充：`DebugToolsConfig.enabled` 为假时恒为 null，避免正式
  /// 包把服务端原文贴到界面上。排查接口时可以直接展示，省得去翻 logcat。
  final String? body;
  final bool? _authError;

  bool get isAuthError => _authError ?? (code == 401 || code == 406);

  @override
  String toString() => 'ApiException($code, $message)';
}
