class AwikiServiceError implements Exception {
  const AwikiServiceError({
    this.statusCode,
    this.rpcCode,
    required this.message,
    this.data,
  });

  final int? statusCode;
  final int? rpcCode;
  final String message;
  final Object? data;

  bool get isUnauthorized =>
      statusCode == 401 || statusCode == 403 || rpcCode == 1401;

  @override
  String toString() {
    if (rpcCode != null) {
      return 'AwikiServiceError rpc $rpcCode: $message';
    }
    if (statusCode != null) {
      return 'AwikiServiceError http $statusCode: $message';
    }
    return 'AwikiServiceError: $message';
  }
}
