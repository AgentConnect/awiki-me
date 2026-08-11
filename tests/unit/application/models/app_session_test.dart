import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSessionLegacyIdentity', () {
    test('uses local alias as legacy credential name when available', () {
      const session = AppSession(
        did: 'did:wba:awiki.ai:user:alice:e1_123',
        identityId: 'identity-1',
        displayName: 'Alice',
        handle: 'alice.awiki.ai',
        localAlias: 'alice-local',
        authenticated: true,
        jwtToken: 'jwt-123',
        accountBinding: SessionAccountBinding(
          ownerIdentityId: 'identity-1',
          accountId: 'account-1',
          currentDid: 'did:wba:awiki.ai:user:alice:e1_123',
          protocolDeviceId: 'protocol-device-1',
          identityGeneration: '3',
          deviceAuthGeneration: '5',
        ),
      );

      final legacy = session.toLegacySessionIdentity();

      expect(legacy.did, 'did:wba:awiki.ai:user:alice:e1_123');
      expect(legacy.localIdentityId, 'identity-1');
      expect(legacy.credentialName, 'alice-local');
      expect(legacy.displayName, 'Alice');
      expect(legacy.handle, 'alice.awiki.ai');
      expect(legacy.jwtToken, 'jwt-123');
      expect(legacy.ownerIdentityId, 'identity-1');
      expect(legacy.accountId, 'account-1');
      expect(legacy.protocolDeviceId, 'protocol-device-1');
    });

    test('falls back to identity id for legacy credential name', () {
      const session = AppSession(
        did: 'did:wba:awiki.ai:user:bob:e1_456',
        identityId: 'identity-2',
        displayName: 'Bob',
      );

      final legacy = session.toLegacySessionIdentity();

      expect(legacy.credentialName, 'identity-2');
      expect(legacy.localIdentityId, 'identity-2');
      expect(legacy.handle, isNull);
      expect(legacy.jwtToken, isNull);
      expect(legacy.accountBinding, isNull);
    });

    test('copyWith retains and can replace the typed account binding', () {
      const initial = SessionAccountBinding(
        ownerIdentityId: 'identity-3',
        accountId: 'account-3',
        currentDid: 'did:wba:awiki.ai:user:carol:e1_789',
        protocolDeviceId: 'protocol-device-3',
        identityGeneration: '7',
        deviceAuthGeneration: '11',
      );
      const replacement = SessionAccountBinding(
        ownerIdentityId: 'identity-3',
        accountId: 'account-3',
        currentDid: 'did:wba:awiki.ai:user:carol:e1_790',
        protocolDeviceId: 'protocol-device-4',
        identityGeneration: '8',
        deviceAuthGeneration: '12',
      );
      const session = AppSession(
        did: 'did:wba:awiki.ai:user:carol:e1_789',
        identityId: 'identity-3',
        displayName: 'Carol',
        accountBinding: initial,
      );

      expect(
        session.copyWith(authenticated: true).accountBinding,
        same(initial),
      );
      expect(
        session.copyWith(accountBinding: replacement).accountBinding,
        same(replacement),
      );
    });
  });
}
