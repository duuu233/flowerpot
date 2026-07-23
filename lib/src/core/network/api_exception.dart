class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.data, bool? authError})
    : _authError = authError;

  final Object code;
  final String message;
  final Object? data;
  final bool? _authError;

  bool get isAuthError => _authError ?? (code == 401 || code == 406);

  @override
  String toString() => 'ApiException($code, $message)';
}
