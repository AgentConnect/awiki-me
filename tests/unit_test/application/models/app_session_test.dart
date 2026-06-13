import 'package:awiki_me/src/application/models/app_session.dart';
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
      );

      final legacy = session.toLegacySessionIdentity();

      expect(legacy.did, 'did:wba:awiki.ai:user:alice:e1_123');
      expect(legacy.credentialName, 'alice-local');
      expect(legacy.displayName, 'Alice');
      expect(legacy.handle, 'alice.awiki.ai');
      expect(legacy.jwtToken, 'jwt-123');
    });

    test('falls back to identity id for legacy credential name', () {
      const session = AppSession(
        did: 'did:wba:awiki.ai:user:bob:e1_456',
        identityId: 'identity-2',
        displayName: 'Bob',
      );

      final legacy = session.toLegacySessionIdentity();

      expect(legacy.credentialName, 'identity-2');
      expect(legacy.handle, isNull);
      expect(legacy.jwtToken, isNull);
    });
  });
}
