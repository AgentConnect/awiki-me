/// A read-only routing hint. It never proves account ownership or reserves a name.
class RegistrationCheck {
  const RegistrationCheck({
    required this.fullHandle,
    required this.decision,
    required this.inviteRequired,
    required this.inviteStatus,
    this.reason,
  });

  final String fullHandle;
  final String decision;
  final bool inviteRequired;
  final String inviteStatus;
  final String? reason;

  bool get isExisting => decision == 'existing';
  bool get canVerify =>
      isExisting ||
      (decision == 'register' && (!inviteRequired || inviteStatus == 'valid'));

  factory RegistrationCheck.fromJson(
    Map<String, Object?> json, {
    required String expectedFullHandle,
  }) {
    final decision = json['decision'];
    final required = json['invite_required'];
    final status = json['invite_status'];
    if (json['full_handle'] != expectedFullHandle ||
        !const {'register', 'existing', 'unavailable'}.contains(decision) ||
        required is! bool ||
        !const {
          'not_required',
          'required',
          'valid',
          'invalid',
        }.contains(status) ||
        (decision == 'existing' && required) ||
        (!required && status != 'not_required') ||
        (required && status == 'not_required')) {
      throw const FormatException('registration_check_invalid');
    }
    return RegistrationCheck(
      fullHandle: expectedFullHandle,
      decision: decision as String,
      inviteRequired: required,
      inviteStatus: status as String,
      reason: json['reason'] as String?,
    );
  }
}
