// Build only in the isolated fixture package with flutter_secure_storage 9.2.4.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final result = <String, Object?>{'phase': 'seed-v9', 'ok': false};
  try {
    if (!Platform.isAndroid ||
        (await PackageInfo.fromPlatform()).packageName != fixturePackage) {
      throw StateError('isolated_fixture_package_required');
    }
    const storage = FlutterSecureStorage();
    const appOptions = AndroidOptions(
      resetOnError: false,
      // ignore: deprecated_member_use
      sharedPreferencesName: 'FlutterSecureStorage',
      preferencesKeyPrefix:
          'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIHNlY3VyZSBzdG9yYWdlCg',
    );
    const scopeOptions = AndroidOptions(
      // ignore: deprecated_member_use
      encryptedSharedPreferences: true,
      resetOnError: false,
      // ignore: deprecated_member_use
      sharedPreferencesName: 'awiki_me_scope_secrets',
      preferencesKeyPrefix: 'awiki_scope_',
    );
    if (await storage.read(key: fixtureSelectionKey, aOptions: appOptions) !=
            null ||
        await storage.read(key: fixtureSecretKey, aOptions: scopeOptions) !=
            null) {
      throw StateError('fixture_already_seeded');
    }
    await storage.write(
      key: fixtureSecretKey,
      value: fixtureEnvelope,
      aOptions: scopeOptions,
    );
    await storage.write(
      key: fixtureSelectionKey,
      value: fixtureIdentity,
      aOptions: appOptions,
    );
    result['scope_matches'] =
        await storage.read(key: fixtureSecretKey, aOptions: scopeOptions) ==
        fixtureEnvelope;
    result['selection_matches'] =
        await storage.read(key: fixtureSelectionKey, aOptions: appOptions) ==
        fixtureIdentity;
    result['ok'] =
        result['scope_matches'] == true && result['selection_matches'] == true;
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
