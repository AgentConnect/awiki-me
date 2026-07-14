import 'package:awiki_me/src/domain/services/peer_display_name_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = PeerDisplayNameResolver();

  test('uses one stable peer display priority', () {
    expect(
      resolver.resolve(
        localNote: 'Local note',
        nickname: 'Nickname',
        fullHandle: 'alice.awiki.info',
        did: 'did:wba:awiki.info:alice:e1_test',
      ),
      'Local note',
    );
    expect(
      resolver.resolve(
        nickname: 'Nickname',
        fullHandle: 'alice.awiki.info',
        did: 'did:wba:awiki.info:alice:e1_test',
      ),
      'Nickname',
    );
    expect(
      resolver.resolve(
        fullHandle: '@alice.awiki.info',
        did: 'did:wba:awiki.info:alice:e1_test',
      ),
      'alice.awiki.info',
    );
  });

  test('uses snapshot only when current profile identity is unavailable', () {
    expect(
      resolver.resolve(
        senderNameSnapshot: 'Historical Alice',
        did: 'did:wba:awiki.info:alice:e1_test',
      ),
      'Historical Alice',
    );
    expect(
      resolver.resolve(
        nickname: 'Current Alice',
        senderNameSnapshot: 'Historical Alice',
        did: 'did:wba:awiki.info:alice:e1_test',
      ),
      'Current Alice',
    );
  });

  test('rejects DID-shaped names and falls back to compact DID or unknown', () {
    const did = 'did:wba:awiki.info:alice:e1_test';
    expect(resolver.resolve(nickname: did, fullHandle: did, did: did), 'alice');
    expect(
      resolver.resolve(nickname: 'alice', did: did),
      'alice',
      reason: 'machine-generated compact DID is not treated as a nickname',
    );
    expect(resolver.resolve(unknownLabel: 'Unknown user'), 'Unknown user');
  });
}
