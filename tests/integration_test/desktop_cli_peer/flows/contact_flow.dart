part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyContactRegression({
  required RelationshipApplicationService relationships,
  required _DesktopCliPeerSmokeConfig config,
}) async {
  final cliDid = await _currentCliDid(config);
  expect(cliDid.trim(), isNotEmpty);

  await _tryIgnore(() => relationships.unfollow(cliDid));
  await _tryIgnore(
    () => _runCli(config, <String>[
      '--format',
      'json',
      'people',
      'unfollow',
      config.appHandle,
    ]),
  );

  await relationships.follow(cliDid);
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expectedAny: const <String>{'following', 'friend'},
  );
  await _waitForAppRelationshipList(
    description: 'App following contains CLI DID',
    load: () => relationships.listFollowing(limit: 50),
    expectedRef: cliDid,
  );
  await _waitForCliRelationshipList(
    config: config,
    command: 'followers',
    expectedRef: config.appHandle,
  );
  await _waitForCliRelationshipStatus(
    config: config,
    peer: config.appHandle,
    expectedRef: config.appHandle,
  );

  final cliFollow = await _runCli(config, <String>[
    '--format',
    'json',
    'people',
    'follow',
    config.appHandle,
  ]);
  if (cliFollow.exitCode != 0) {
    fail('CLI people follow failed: ${_summarizeCliResult(cliFollow)}');
  }

  await _waitForAppRelationshipList(
    description: 'App followers contain CLI handle',
    load: () => relationships.listFollowers(limit: 50),
    expectedRef: cliDid,
  );
  await _waitForCliRelationshipList(
    config: config,
    command: 'following',
    expectedRef: config.appHandle,
  );
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expectedAny: const <String>{'friend', 'follower', 'following'},
  );

  await relationships.unfollow(cliDid);
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expectedAny: const <String>{'follower', 'none'},
  );
  await _waitForAppRelationshipListAbsent(
    description: 'App following no longer contains CLI DID',
    load: () => relationships.listFollowing(limit: 50),
    unexpectedRef: cliDid,
  );

  final cliUnfollow = await _runCli(config, <String>[
    '--format',
    'json',
    'people',
    'unfollow',
    config.appHandle,
  ]);
  if (cliUnfollow.exitCode != 0) {
    fail('CLI people unfollow failed: ${_summarizeCliResult(cliUnfollow)}');
  }
}

Future<String> _currentCliDid(_DesktopCliPeerSmokeConfig config) async {
  final current = await _runCli(config, const <String>[
    '--format',
    'json',
    'id',
    'current',
  ]);
  if (current.exitCode != 0) {
    fail('CLI id current failed: ${_summarizeCliResult(current)}');
  }
  final did = _jsonStringAt(current.stdout, const <Object>[
    'data',
    'identity',
    'did',
  ]);
  if (did == null || did.trim().isEmpty) {
    fail('CLI id current did missing: ${_summarizeCliResult(current)}');
  }
  return did;
}

Future<void> _waitForAppRelationshipStatus({
  required RelationshipApplicationService relationships,
  required String peer,
  required Set<String> expectedAny,
}) async {
  await _poll(
    description: 'App relationship status for "$peer" is one of $expectedAny',
    action: () async {
      final status = await relationships.status(peer);
      return expectedAny.contains(status.relationship.trim().toLowerCase());
    },
  );
}

Future<void> _waitForAppRelationshipList({
  required String description,
  required Future<CoreRelationshipPage> Function() load,
  required String expectedRef,
}) async {
  await _poll(
    description: description,
    action: () async {
      final page = await load();
      return page.items.any(
        (item) => _relationshipMatchesRef(item, expectedRef),
      );
    },
  );
}

Future<void> _waitForAppRelationshipListAbsent({
  required String description,
  required Future<CoreRelationshipPage> Function() load,
  required String unexpectedRef,
}) async {
  await _poll(
    description: description,
    action: () async {
      final page = await load();
      return !page.items.any(
        (item) => _relationshipMatchesRef(item, unexpectedRef),
      );
    },
  );
}

Future<void> _waitForCliRelationshipList({
  required _DesktopCliPeerSmokeConfig config,
  required String command,
  required String expectedRef,
}) async {
  await _poll(
    description: 'CLI people $command contains "$expectedRef"',
    action: () async {
      final result = await _runCli(config, <String>[
        '--format',
        'json',
        'people',
        command,
        '--limit',
        '50',
        '--profile',
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return _jsonContainsText(result.stdout, expectedRef);
    },
  );
}

Future<void> _waitForCliRelationshipStatus({
  required _DesktopCliPeerSmokeConfig config,
  required String peer,
  required String expectedRef,
}) async {
  await _poll(
    description: 'CLI people status for "$peer" contains "$expectedRef"',
    action: () async {
      final result = await _runCli(config, <String>[
        '--format',
        'json',
        'people',
        'status',
        peer,
      ]);
      if (result.exitCode != 0) {
        return false;
      }
      return _jsonContainsText(result.stdout, expectedRef);
    },
  );
}

bool _relationshipMatchesRef(RelationshipSummary item, String ref) {
  final expected = _normalizeIdentityRef(ref);
  if (expected.isEmpty) {
    return false;
  }
  final fields = <String>[
    item.did,
    item.handle ?? '',
    item.displayName,
  ].map(_normalizeIdentityRef).where((field) => field.isNotEmpty);
  return fields.any(
    (field) =>
        field == expected ||
        field.contains(expected) ||
        expected.contains(field),
  );
}

Future<void> _tryIgnore(Future<Object?> Function() action) async {
  try {
    await action();
  } on Object {
    // Best-effort cleanup for reused non-production E2E identities.
  }
}
