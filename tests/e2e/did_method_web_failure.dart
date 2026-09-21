/// Closed stage names for the Web UI driver; arbitrary failure text stays private.
String? didWebRegistrationFailureStage(String? message) => const {
  'Configured service did not advertise both creation methods.':
      'creation_discovery',
  'New identity creation no longer defaults to WBA.': 'default_method',
  'Web creation option was not visible.': 'method_picker',
  'Web selection omitted the first-admin loss limitation.': 'admin_limitation',
  'Web registration OTP action was unavailable.': 'otp_action',
  'Web registration OTP did not complete.': 'otp_response',
  'Web registration submit was unavailable.': 'submit_action',
  'Visible Web registration did not activate a Web identity.': 'activation',
}[message];
