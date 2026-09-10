import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'sync_recovery_operator_contract.dart';

void validateAppPairCleanupPreflight(String output) {
  final Object? receipt = jsonDecode(output);
  if (receipt is! Map ||
      receipt.length != 5 ||
      receipt['schemaVersion'] != 1 ||
      receipt['service'] != 'message-service' ||
      receipt['action'] != 'system_test_app_scope_cleanup_preflight' ||
      receipt['ready'] != true ||
      receipt['code'] != 'ready') {
    throw const FormatException('cleanup_preflight_invalid');
  }
}

List<String> appPairMessageCleanupCommand(String mode) =>
    reviewedSyncRecoveryOperatorCommandForMode(mode)
        .map(
          (arg) => arg.replaceAll(
            '/prepare_sync_v2_recovery_test.py',
            '/cleanup_system_test_scope.py',
          ),
        )
        .toList(growable: false);

String appPairCleanupRequest(List<String> accountIds) {
  if (accountIds.isEmpty ||
      accountIds.length > 2 ||
      accountIds.toSet().length != accountIds.length ||
      accountIds.any(
        (id) => !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$').hasMatch(id),
      )) {
    throw const FormatException('cleanup_scope_invalid');
  }
  return jsonEncode({
    'action': 'cleanup_test_app_scope',
    'account_ids': accountIds,
  });
}

String appPairCleanupFingerprint(List<String> accountIds) {
  appPairCleanupRequest(accountIds);
  return sha256
      .convert(
        utf8.encode(
          'awiki.system-test.cleanup.account-scope.v1\u0000${jsonEncode(accountIds.toList()..sort())}',
        ),
      )
      .toString();
}

Map<String, Object?> validateAppPairCleanupReceipt(
  String output, {
  required List<String> accountIds,
}) {
  const domains = {
    'account',
    'attachment',
    'direct',
    'group',
    'outbox',
    'sync',
  };
  final Object? receipt = jsonDecode(output);
  final counts = receipt is Map ? receipt['deletedCounts'] : null;
  if (receipt is! Map ||
      receipt.length != 8 ||
      receipt['schemaVersion'] != 1 ||
      receipt['service'] != 'message-service' ||
      receipt['action'] != 'system_test_app_scope_cleanup' ||
      receipt['scopeFingerprint'] != appPairCleanupFingerprint(accountIds) ||
      receipt['authorizedAccountCount'] != accountIds.length ||
      receipt['residualCount'] != 0 ||
      receipt['cleaned'] != true ||
      counts is! Map ||
      counts.length != domains.length ||
      !domains.every(counts.containsKey) ||
      counts.values.any((value) => value is! int || value < 0)) {
    throw const FormatException('cleanup_receipt_invalid');
  }
  return {
    'status': 'cleaned',
    'scope': 'registered_app_pair_and_owned_agents_message_data',
    'scopeFingerprint': receipt['scopeFingerprint'],
    'deletedCounts': Map<String, Object?>.from(counts),
    'residualCount': 0,
  };
}
