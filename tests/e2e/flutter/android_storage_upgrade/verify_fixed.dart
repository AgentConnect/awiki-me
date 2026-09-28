import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/key_value_active_session_store.dart';
import 'package:awiki_me/src/data/storage/platform_scope_secret_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final result = <String, Object?>{'phase': 'fixed', 'ok': false};
  try {
    if (!Platform.isAndroid ||
        (await PackageInfo.fromPlatform()).packageName != fixturePackage) {
      throw StateError('isolated_fixture_package_required');
    }
    // Exercise the production adapters and real Android plugin/Keystore.
    final secrets = FlutterSecureScopeSecretPlatformStore();
    result['scope_matches'] =
        await secrets.read(
          service: kReleaseMode
              ? 'ai.awiki.awikime.scope-secrets'
              : 'ai.awiki.awikime.dev.scope-secrets',
          account: fixtureSecretKey,
        ) ==
        fixtureEnvelope;
    KeyValueActiveSessionStore selection() => KeyValueActiveSessionStore(
      storage: SecureAppKeyValueStore(),
      scopeId: StorageScopeId.parse(fixtureScope),
    );
    final initial = await selection().readActiveIdentityId();
    result['selection_initial'] = initial == null
        ? 'absent'
        : initial == fixtureIdentity
        ? 'matches'
        : 'unexpected';
    if (initial == null) {
      // Simulate the state write after explicit validated identity selection.
      // This probe does not claim real-account authentication or vault open.
      await selection().writeActiveIdentityId(fixtureIdentity);
    }
    result['selection_persists'] =
        await selection().readActiveIdentityId() == fixtureIdentity;
    result['ok'] =
        result['scope_matches'] == true &&
        result['selection_initial'] != 'unexpected' &&
        result['selection_persists'] == true;
  } on Object catch (error) {
    result['error_type'] = error.runtimeType.toString();
  }
  final output = jsonEncode(result);
  // ignore: avoid_print
  print('AWIKI_STORAGE_FIXTURE $output');
  runApp(
    MaterialApp(
      home: Scaffold(body: Center(child: Text(output))),
    ),
  );
}
