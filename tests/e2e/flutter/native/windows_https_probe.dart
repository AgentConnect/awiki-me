// Read-only field probe. Does not initialize App/Core/account storage.
import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/core/app_error_classifier.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/app_update_service.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:flutter/widgets.dart';

class _MemoryStore implements AppKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async => values.remove(key);
}

// Dart's default Windows roots come from its built-in Mozilla list.
// This does not inspect the Windows OS certificate store.
Future<String> _dartDefaultTrustOnly() async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse(
        'https://anpclaw.com/user-service/v1/server-info?client_platform=app',
      ),
    );
    final response = await request.close();
    await response.drain<void>();
    return 'http_${response.statusCode}';
  } on TlsException {
    return 'tls_rejected';
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['AWIKI_HTTPS_PROBE_REPORT'];
  if (!Platform.isWindows || path == null) exit(2);
  final report = <String, Object?>{
    'app_source': const String.fromEnvironment('AWIKI_APP_SOURCE_REF'),
    'host': 'anpclaw.com',
    'actual_account_login': 'manual_pending',
  };
  final utility = AwikiOnboardingUtilityHttpClient(
    baseUrl: 'https://anpclaw.com',
  );
  final update = AppUpdateService(
    storage: _MemoryStore(),
    tenantId: 'https-probe',
    backendBaseUrl: 'https://anpclaw.com',
  );
  var status = 1;
  try {
    report['dart_default_before'] = await _dartDefaultTrustOnly().timeout(
      const Duration(seconds: 20),
    );
    final result = await AwikiOnboardingUtilityClient(
      serviceClient: utility,
    ).checkRegistration(handle: 'tlsprobe0924', domain: 'anpclaw.com');
    if (![
      'register',
      'existing',
      'join_or_recover',
      'unavailable',
    ].contains(result['decision'])) {
      throw StateError('unexpected_registration_decision');
    }
    report['registration_check'] = 'passed';
    final policy = await update.checkForUpdates(force: true);
    if (policy.latestManifest == null || policy.failureReason != null) {
      throw StateError('update_policy_missing');
    }
    report['update_check'] = 'passed';
    report['policy_revision'] = policy.latestManifest!.policyRevision;
    report['dart_default_after'] = await _dartDefaultTrustOnly().timeout(
      const Duration(seconds: 20),
    );
    status = 0;
  } catch (error) {
    report['error_code'] =
        structuredAppErrorCode(error) ?? error.runtimeType.toString();
  } finally {
    utility.close();
    update.dispose();
    report['passed'] = status == 0;
    await File(
      path,
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  }
  exit(status);
}
