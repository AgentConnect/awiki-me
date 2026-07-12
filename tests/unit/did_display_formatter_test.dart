import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/shared/formatters/display_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compactDid only recognizes e1 DID user segment', () {
    expect(
      DidDisplayFormatter.compactDid('did:wba:awiki.ai:user:alice:e1_key'),
      'alice',
    );
    expect(
      DidDisplayFormatter.compactDid('did:wba:awiki.ai:user:alice:k1_legacy'),
      'k1_legacy',
    );
  });

  test('profileName falls back from display name to handle and DID', () {
    expect(
      DidDisplayFormatter.profileName(
        const UserProfile(
          did: 'did:wba:awiki.ai:user:alice:e1_key',
          displayName: 'Alice',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'alice.awiki.ai',
        ),
      ),
      'Alice',
    );
    expect(
      DidDisplayFormatter.profileName(
        const UserProfile(
          did: 'did:wba:awiki.ai:user:bob:e1_key',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'bob.awiki.ai',
        ),
      ),
      'bob.awiki.ai',
    );
  });

  test('relationship title prefers nickname then Handle then DID', () {
    expect(
      DidDisplayFormatter.relationshipTitle(
        const RelationshipSummary(
          did: 'did:wba:awiki.ai:user:alice:e1_key',
          displayName: 'Alice',
          handle: 'alice.awiki.ai',
          relationship: 'following',
        ),
      ),
      'Alice',
    );
    expect(
      DidDisplayFormatter.relationshipTitle(
        const RelationshipSummary(
          did: 'did:wba:awiki.ai:user:bob:e1_key',
          displayName: 'did:wba:awiki.ai:user:bob:e1_key',
          handle: '@bob.awiki.ai',
          relationship: 'follower',
        ),
      ),
      'bob.awiki.ai',
    );
    expect(
      DidDisplayFormatter.relationshipTitle(
        const RelationshipSummary(
          did: 'did:wba:awiki.ai:user:carol:e1_key',
          displayName: '',
          relationship: 'follower',
        ),
      ),
      'carol',
    );
  });

  test('compactDidPath preserves DID path and fingerprint tail', () {
    const did =
        'did:wba:awiki.ai:user:alice:e1_abcdefghijklmnopqrstuvwxyz0123456789';

    final compact = DidDisplayFormatter.compactDidPath(did);

    expect(compact, startsWith('did:wba:awiki.ai:user:alice:e1_'));
    expect(compact, contains('…'));
    expect(compact, endsWith('yz0123456789'));
    expect(compact.length, lessThan(did.length));
  });

  test('profile handle label prefers fullHandle and name stays secondary', () {
    const profile = UserProfile(
      did: 'did:wba:awiki.ai:alice:e1_key',
      displayName: 'Alice Zhang',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      handle: 'alice',
      fullHandle: '@alice.awiki.ai',
    );

    expect(DidDisplayFormatter.profileHandleLabel(profile), '@alice.awiki.ai');
    expect(DidDisplayFormatter.secondaryProfileName(profile), 'Alice Zhang');
  });

  test('profile metadata cleaner only removes exact handle and DID lines', () {
    const markdown = '''
# About me

我的短号(handle)：alice.awiki.ai
DID: did:wba:awiki.ai:alice:e1_key

I use DID: examples in free-form prose.
''';

    expect(
      DidDisplayFormatter.withoutRedundantIdentityMetadata(markdown),
      '# About me\n\nI use DID: examples in free-form prose.',
    );
  });

  test('homepageUrl uses profileUri then handle and never displayName', () {
    expect(
      DidDisplayFormatter.homepageUrl(
        const UserProfile(
          did: 'did:alice',
          displayName: 'Alice',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          profileUri: 'https://profiles.example/alice',
          handle: 'alice.awiki.ai',
        ),
      ),
      'https://profiles.example/alice',
    );
    expect(
      DidDisplayFormatter.homepageUrl(
        const UserProfile(
          did: 'did:bob',
          displayName: 'Bob',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'bob.awiki.ai',
        ),
      ),
      'https://bob.awiki.ai',
    );
    expect(
      DidDisplayFormatter.homepageUrl(
        const UserProfile(
          did: 'did:carol',
          displayName: 'Carol',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
        ),
      ),
      isEmpty,
    );
    expect(
      DidDisplayFormatter.homepageUrl(
        const UserProfile(
          did: 'did:dana',
          displayName: 'Dana',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          profileUri: 'http://profiles.example/dana',
        ),
      ),
      isEmpty,
    );
    expect(
      DidDisplayFormatter.homepageUrl(
        const UserProfile(
          did: 'did:erin',
          displayName: 'Erin',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'http://erin.example',
        ),
      ),
      isEmpty,
    );
  });
}
