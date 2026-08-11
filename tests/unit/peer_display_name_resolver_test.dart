import 'package:awiki_me/src/domain/services/peer_display_name_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = PeerDisplayNameResolver();

  test('uses one stable peer display priority', () {
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

  test('removes the domain only from handle-shaped visible names', () {
    expect(
      resolver.resolve(
        nickname: 'alice.awiki.info',
        fullHandle: 'alice.awiki.info',
        compactQualifiedHandle: true,
      ),
      'alice',
    );
    expect(
      resolver.resolve(
        senderNameSnapshot: '@bob.agent-connect.cn',
        compactQualifiedHandle: true,
      ),
      'bob',
    );
    expect(
      resolver.resolve(
        nickname: 'Alice Zhang',
        fullHandle: 'alice.awiki.info',
        compactQualifiedHandle: true,
      ),
      'Alice Zhang',
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
