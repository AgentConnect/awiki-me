enum DeviceRevokeOutcomeCategory {
  cancelledBeforeSubmit,
  rejectedBeforeCommit,
  outcomeUnknown,
}

class DeviceRevokeException implements Exception {
  const DeviceRevokeException(this.category, {this.code});

  final DeviceRevokeOutcomeCategory category;
  final String? code;
}
