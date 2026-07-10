part of '../desktop_cli_peer_e2e.dart';

Future<void> _verifyContactRegression({
  required _DesktopAppRobot robot,
  required RelationshipApplicationService relationships,
  required _DesktopCliPeerSmokeConfig config,
}) async {
  final cliDid = await _currentCliDid(config);
  expect(cliDid.trim(), isNotEmpty);

  // Reused remote identities require an explicit baseline. Cleanup is setup,
  // while every relationship transition under test is driven by App UI or CLI.
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
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'none',
  );

  final conversation = await robot.startDirectConversation(config.cliHandle);
  expect(conversation.targetDid, cliDid);
  await robot.followSelectedPeer();
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'following',
  );
  await _waitForAppRelationshipList(
    description: 'App following contains exact CLI DID',
    load: () => relationships.listFollowing(limit: 50),
    expectedDid: cliDid,
  );
  await _waitForCliRelationshipList(
    config: config,
    command: 'followers',
    expectedDidOrHandle: config.appHandle,
  );
  await _waitForCliRelationshipStatus(
    config: config,
    peer: config.appHandle,
    expectedRelationship: 'follower',
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
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'friend',
  );
  await _waitForAppRelationshipList(
    description: 'App followers contain exact CLI DID',
    load: () => relationships.listFollowers(limit: 50),
    expectedDid: cliDid,
  );
  await _waitForCliRelationshipList(
    config: config,
    command: 'following',
    expectedDidOrHandle: config.appHandle,
  );

  await robot.unfollowSelectedPeer();
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'follower',
  );
  await _waitForAppRelationshipListAbsent(
    description: 'App following excludes exact CLI DID',
    load: () => relationships.listFollowing(limit: 50),
    unexpectedDid: cliDid,
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
  await _waitForAppRelationshipStatus(
    relationships: relationships,
    peer: cliDid,
    expected: 'none',
  );
  await _waitForCliRelationshipStatus(
    config: config,
    peer: config.appHandle,
    expectedRelationship: 'none',
  );
  await robot.closePeerInfo();
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
  required String expected,
}) async {
  await _poll(
    description: 'App relationship status for "$peer" equals $expected',
    action: () async {
      final status = await relationships.status(peer);
      return status.relationship.trim().toLowerCase() == expected;
    },
  );
}

Future<void> _waitForAppRelationshipList({
  required String description,
  required Future<CoreRelationshipPage> Function() load,
  required String expectedDid,
}) async {
  await _poll(
    description: description,
    action: () async {
      final page = await load();
      return page.items
              .where((item) => item.did.trim() == expectedDid)
              .length ==
          1;
    },
  );
}

Future<void> _waitForAppRelationshipListAbsent({
  required String description,
  required Future<CoreRelationshipPage> Function() load,
  required String unexpectedDid,
}) async {
  await _poll(
    description: description,
    action: () async {
      final page = await load();
      return page.items.every((item) => item.did.trim() != unexpectedDid);
    },
  );
}

Future<void> _waitForCliRelationshipList({
  required _DesktopCliPeerSmokeConfig config,
  required String command,
  required String expectedDidOrHandle,
}) async {
  await _poll(
    description: 'CLI people $command contains exact "$expectedDidOrHandle"',
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
      return _cliRelationshipListExactCount(
            result.stdout,
            expectedDidOrHandle,
          ) ==
          1;
    },
  );
}

Future<void> _waitForCliRelationshipStatus({
  required _DesktopCliPeerSmokeConfig config,
  required String peer,
  required String expectedRelationship,
}) async {
  await _poll(
    description: 'CLI people status for "$peer" equals $expectedRelationship',
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
      return cliRelationshipState(result.stdout) ==
          expectedRelationship.trim().toLowerCase();
    },
  );
}

int _cliRelationshipListExactCount(String output, String expectedRef) {
  final expected = _normalizeIdentityRef(expectedRef);
  if (expected.isEmpty) {
    return 0;
  }
  final items = _jsonValueAt(output, const <Object>['data', 'items']);
  if (items is! List) {
    return 0;
  }
  return items.whereType<Map>().where((item) {
    final map = _cliStringKeyMap(item);
    final did = _normalizeIdentityRef(map['did']?.toString() ?? '');
    final handle = _normalizeIdentityRef(map['handle']?.toString() ?? '');
    return did == expected || handle == expected;
  }).length;
}

Future<void> _tryIgnore(Future<Object?> Function() action) async {
  try {
    await action();
  } on Object {
    // Best-effort cleanup for reused non-production E2E identities.
  }
}
