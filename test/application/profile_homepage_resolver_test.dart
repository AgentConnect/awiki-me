import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/profile_homepage_resolver.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseProfile = UserProfile(
    did: 'did:wba:anpclaw.com:zhuocheng:e1_key',
    nickName: 'Zhuocheng',
    bio: '',
    tags: <String>[],
    profileMarkdown: '',
    handle: 'zhuocheng',
  );

  test('full handle is the canonical homepage source', () {
    final resolver = ProfileHomepageResolver(
      environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
    );

    expect(
      resolver.homepageUrl(
        baseProfile.copyWith(fullHandle: 'zhuocheng.anpclaw.com'),
      ),
      'https://zhuocheng.anpclaw.com',
    );
  });

  test('did domain wins over environment for bare handle profiles', () {
    final resolver = ProfileHomepageResolver(
      environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
    );

    expect(resolver.homepageUrl(baseProfile), 'https://zhuocheng.anpclaw.com');
  });

  test('environment domain is only a fallback when DID has no WBA domain', () {
    final resolver = ProfileHomepageResolver(
      environment: AwikiEnvironmentConfig(baseUrl: 'https://anpclaw.com'),
    );

    expect(
      resolver.homepageUrl(
        const UserProfile(
          did: 'did:test',
          nickName: 'Zhuocheng',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'zhuocheng',
        ),
      ),
      'https://zhuocheng.anpclaw.com',
    );
  });

  test('user handle can be derived from DID when handle is absent', () {
    final resolver = ProfileHomepageResolver(
      environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
    );

    expect(
      resolver.homepageUrl(
        const UserProfile(
          did: 'did:wba:anpclaw.com:user:zhuocheng:e1_key',
          nickName: 'Zhuocheng',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
        ),
      ),
      'https://zhuocheng.anpclaw.com',
    );
  });

  test('domain-qualified handle is preserved', () {
    final resolver = ProfileHomepageResolver(
      environment: AwikiEnvironmentConfig(baseUrl: 'https://anpclaw.com'),
    );

    expect(
      resolver.homepageUrl(
        const UserProfile(
          did: 'did:test',
          nickName: 'Zhuocheng',
          bio: '',
          tags: <String>[],
          profileMarkdown: '',
          handle: 'zhuocheng.awiki.ai',
        ),
      ),
      'https://zhuocheng.awiki.ai',
    );
  });
}
