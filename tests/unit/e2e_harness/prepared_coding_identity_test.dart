import 'dart:convert';
import 'dart:io';

import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../e2e/prepared_coding_identity.dart';
import '../../e2e/flutter/support/coding_agent_oracles.dart';

void main() {
  const previous = '20260915180040-hmbmriu5ey';
  late Directory root;
  late Directory fixture;
  setUp(() {
    root = Directory.systemTemp.createTempSync('acp-prepared-identity-unit-');
    fixture = Directory('${root.path}/.e2e/acp-agent/$previous');
    for (final name in ['app', 'cli-peer', 'cli-home', 'reports']) {
      Directory('${fixture.path}/$name').createSync(recursive: true);
    }
    File('${fixture.path}/reports/resource_ledger.json').writeAsStringSync(
      jsonEncode({
        'runId': previous,
        'suite': 'acp-agent',
        'scenario': 'acp-agent-full-ui',
      }),
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  PreparedCodingIdentity? resolve({
    String? id = previous,
    String suite = 'acp-agent',
  }) => PreparedCodingIdentity.resolve(
    root: root,
    suite: suite,
    currentRunId: '20260916050000-newrun1234',
    preparedRunId: id,
  );

  test(
    'fresh execution is the default and explicit selection preserves roots',
    () {
      expect(resolve(id: null), isNull);
      final prepared = resolve()!;
      expect(prepared.runId, previous);
      expect(prepared.app.path, '${fixture.path}/app');
      expect(prepared.cli.path, '${fixture.path}/cli-peer');
      final lease = prepared.acquireLease();
      lease.closeSync();
    },
  );
  test('rejects path traversal, unrelated suites and missing ownership', () {
    expect(() => resolve(id: '../other-root'), throwsStateError);
    expect(() => resolve(suite: 'messaging'), throwsStateError);
    File('${fixture.path}/reports/resource_ledger.json').deleteSync();
    expect(resolve, throwsStateError);
  });
  test('rejects a mismatched ledger and missing state', () {
    final ledger = File('${fixture.path}/reports/resource_ledger.json');
    final good = ledger.readAsStringSync();
    ledger.writeAsStringSync(good.replaceAll(previous, 'different-run'));
    expect(resolve, throwsStateError);
    ledger.writeAsStringSync(good);
    Directory('${fixture.path}/app').deleteSync();
    expect(resolve, throwsStateError);
  });
  test('rejects state symlinks to another identity', () {
    Directory('${fixture.path}/app').deleteSync();
    final outside = Directory('${root.path}/unrelated')..createSync();
    Link('${fixture.path}/app').createSync(outside.path);
    expect(resolve, throwsStateError);
  });

  const session = AppSession(
    did: 'did:wba:anpclaw.com:example',
    identityId: 'local-example',
    displayName: 'test',
    handle: 'example.anpclaw.com',
    authenticated: true,
    accountBinding: SessionAccountBinding(
      ownerIdentityId: 'owner',
      accountId: 'account',
      currentDid: 'did:wba:anpclaw.com:example',
      protocolDeviceId: 'device',
      identityGeneration: '1',
      deviceAuthGeneration: '1',
    ),
  );
  test('restores exact prepared session without registration', () async {
    var registrations = 0;
    final actual = await prepareCodingAgentSession(
      reusePreparedIdentity: true,
      expectedFullHandle: 'example.anpclaw.com',
      restore: () async => session,
      register: () async {
        registrations++;
        return session;
      },
    );
    expect(actual, same(session));
    expect(registrations, 0);
  });
  test('logged out prepared account logs in by its exact Core ID', () async {
    String? selected;
    final actual = await restorePreparedCodingAccount(
      expectedFullHandle: 'example.anpclaw.com',
      list: () async => [session.copyWith(authenticated: false)],
      login: (id) async {
        selected = id;
        return session;
      },
    );
    expect(selected, session.identityId);
    expect(actual, same(session));
  });
  test(
    'missing or duplicate account does not select the first local identity',
    () async {
      var logins = 0;
      for (final identities in <List<AppSession>>[
        [],
        [session, session],
        [session.copyWith(handle: 'example.other.test')],
      ]) {
        await expectLater(
          restorePreparedCodingAccount(
            expectedFullHandle: 'example.anpclaw.com',
            list: () async => identities,
            login: (id) async {
              logins++;
              return session;
            },
          ),
          throwsStateError,
        );
      }
      expect(logins, 0);
    },
  );
  test(
    'missing, wrong or unauthenticated prepared account never registers',
    () async {
      var registrations = 0;
      for (final restored in [
        null,
        session.copyWith(handle: 'another.anpclaw.com'),
        session.copyWith(authenticated: false),
      ]) {
        await expectLater(
          prepareCodingAgentSession(
            reusePreparedIdentity: true,
            expectedFullHandle: 'example.anpclaw.com',
            restore: () async => restored,
            register: () async {
              registrations++;
              return session;
            },
          ),
          throwsStateError,
        );
      }
      expect(registrations, 0);
    },
  );
  test(
    'fresh mode registers without reading a different existing session',
    () async {
      var restorations = 0;
      final actual = await prepareCodingAgentSession(
        reusePreparedIdentity: false,
        expectedFullHandle: 'example.anpclaw.com',
        restore: () async {
          restorations++;
          return null;
        },
        register: () async => session,
      );
      expect(actual, same(session));
      expect(restorations, 0);
    },
  );
}
