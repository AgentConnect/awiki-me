/// Test diagnostics accept only closed categories, never server warning bodies.
String closedNetworkFailureReason(String? message) {
  if (message == null) return 'none';
  var value = message;
  const prefix = 'transport unavailable: ';
  for (var count = 0; count < 3 && value.startsWith(prefix); count++) {
    value = value.substring(prefix.length);
  }
  const allowed = {
    'direct_connect',
    'invalid_system_proxy',
    'network_client_initialization',
    'network_connect_timeout',
    'network_method',
    'network_no_alternate_route',
    'network_policy_changed',
    'network_request_failed',
    'network_request_invalid',
    'network_response_timeout',
    'network_tls_handshake',
    'network_tls_name',
    'network_url_host',
    'network_url_port',
    'network_url',
    'proxy_auth_unsupported',
    'proxy_connect',
    'proxy_scheme_unsupported',
    'proxy_socks_connect',
    'proxy_tunnel_headers',
    'proxy_tunnel_rejected',
    'proxy_tunnel_response',
    'proxy_tunnel',
    'proxy_unavailable',
    'system_proxy_resolution',
    'system_proxy_timeout',
    'system_proxy_worker',
  };
  return allowed.contains(value) ? value : 'unrecognized';
}

List<String> recoveryReadWarningCategories(Iterable<String> warnings) {
  final categories = <String>{};
  for (final warning in warnings) {
    categories.add(switch (warning) {
      'Read watermark is queued behind an in-flight predecessor' =>
        'predecessor_in_flight',
      _ when warning.startsWith('Failed to commit read-state ACK:') =>
        'local_ack_failed',
      _ when warning.startsWith('Invalid read-state ACK:') =>
        'invalid_remote_ack',
      _ when warning.startsWith('Remote read-state mark-read failed:') =>
        'remote_read_failed',
      _ when warning.startsWith('Failed to commit fallback ACK:') =>
        'fallback_local_ack_failed',
      _ => 'unrecognized',
    });
  }
  return categories.toList()..sort();
}

List<int> recoveryReadHttpStatuses(Iterable<String> warnings) {
  final statuses = <int>{};
  final pattern = RegExp(r'\bservice error ([1-5][0-9]{2})(?: \(|:)');
  for (final warning in warnings) {
    for (final match in pattern.allMatches(warning)) {
      statuses.add(int.parse(match.group(1)!));
    }
  }
  return statuses.toList()..sort();
}

List<String> recoveryReadServiceCodes(Iterable<String> warnings) {
  const allowed = {
    'READ_STATE_FALLBACK_PENDING',
    'READ_STATE_FALLBACK_RETRY',
    'READ_STATE_INCOMPLETE_ACK',
    'READ_STATE_INVALID_ACK',
    'READ_STATE_LOCAL_ACK_FAILED',
    'READ_STATE_RETRY',
    'READ_STATE_UNSUPPORTED',
  };
  return allowed
      .where((code) => warnings.any((warning) => warning.contains('($code)')))
      .toList()
    ..sort();
}

String closedOnboardingFailureCode(String? value) {
  if (value == null) return 'none';
  const allowed = {
    'request_timeout',
    'session_transition_superseded',
    'state_error',
    'invalid_argument',
    'unclassified_error',
    'identity.registration_verification_unavailable',
    'identity.local_registry_conflict',
    'handle_recovery.local_state_conflict',
    'handle_recovery.transition_missing',
    'handle_recovery.join_terminal_wait',
    'invite_required',
    'invite_length_six',
    'invite_length_max_64',
    'check_failed',
    'handle_unavailable',
    'network_unavailable',
    'request_timeout_retry',
  };
  return allowed.contains(value) ? value : 'unrecognized';
}

String closedOnboardingFeedbackId(String? value) {
  if (value == null) return 'none';
  const allowed = {
    'operationFailedRetry',
    'requestTimeoutRetry',
    'secureConnectionFailed',
    'trustResourcesInvalid',
    'registrationLocalStateNeedsAttention',
    'registrationContinuityChanged',
    'registrationMethodUnavailable',
    'authRequired',
    'networkUnavailable',
    'requestFailed',
    'otpSent',
    'otpRateLimited',
  };
  return allowed.contains(value) ? value : 'unrecognized';
}
