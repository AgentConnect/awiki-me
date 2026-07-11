import 'dart:io';

import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/key_value_active_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active identity is isolated by immutable storage scope', () async {
    final root = await Directory.systemTemp.createTemp('active_scope_test_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final storage = FileAppKeyValueStore.forFile(
      File('${root.path}/state.json'),
    );
    final first = KeyValueActiveSessionStore(
      storage: storage,
      scopeId: StorageScopeId.parse('55555555-5555-4555-8555-555555555555'),
    );
    final second = KeyValueActiveSessionStore(
      storage: storage,
      scopeId: StorageScopeId.parse('66666666-6666-4666-8666-666666666666'),
    );

    await first.writeActiveIdentityId('identity-a');

    expect(await first.readActiveIdentityId(), 'identity-a');
    expect(await second.readActiveIdentityId(), isNull);
    await second.writeActiveIdentityId('identity-b');
    expect(await first.readActiveIdentityId(), 'identity-a');
    expect(await second.readActiveIdentityId(), 'identity-b');
  });
}
