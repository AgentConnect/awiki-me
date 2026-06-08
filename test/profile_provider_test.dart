import 'dart:async';

import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/profile_homepage_resolver.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/profile/profile_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  test('个人资料刷新后保留已加载的主页 markdown 作为可见内容', () async {
    const remoteMarkdown = '# Remote title\n\n# 如何与我通信\n\nRemote body';
    const serverProfile = UserProfile(
      did: 'did:test:bob',
      nickName: 'Bob',
      bio: 'Initial bio',
      tags: <String>[],
      profileMarkdown: '# Bob',
      handle: 'bob',
    );
    final gateway = FakeAwikiGateway()..myProfile = serverProfile;
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        profileApplicationServiceProvider.overrideWithValue(
          FakeProfileApplicationService(gateway),
        ),
        profileHomepageResolverProvider.overrideWithValue(
          ProfileHomepageResolver(
            environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
          ),
        ),
        homepageMarkdownLoaderProvider.overrideWithValue(
          (_) async => remoteMarkdown,
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(profileProvider.notifier);
    await controller.refresh();
    await controller.loadHomepageMarkdown('https://bob.awiki.ai');

    expect(container.read(profileProvider).profile?.profileMarkdown, '# Bob');
    expect(controller.visibleProfileContent(), remoteMarkdown);

    gateway.myProfile = serverProfile.copyWith(
      bio: 'Refreshed bio',
      profileMarkdown: '# Bob',
    );
    await controller.refresh();

    final refreshed = container.read(profileProvider).profile;
    expect(refreshed?.bio, 'Refreshed bio');
    expect(refreshed?.profileMarkdown, '# Bob');
    expect(controller.visibleProfileContent(), remoteMarkdown);
  });

  test('主页 markdown 慢请求返回后不会覆盖最新 profile 状态', () async {
    const remoteMarkdown = '# Remote title\n\n# 如何与我通信\n\nRemote body';
    const serverProfile = UserProfile(
      did: 'did:test:carol',
      nickName: 'Carol',
      bio: 'Initial bio',
      tags: <String>[],
      profileMarkdown: '# Carol',
      handle: 'carol',
    );
    final homepageCompleter = Completer<String?>();
    final gateway = FakeAwikiGateway()..myProfile = serverProfile;
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        profileApplicationServiceProvider.overrideWithValue(
          FakeProfileApplicationService(gateway),
        ),
        profileHomepageResolverProvider.overrideWithValue(
          ProfileHomepageResolver(
            environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
          ),
        ),
        homepageMarkdownLoaderProvider.overrideWithValue(
          (_) => homepageCompleter.future,
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(profileProvider.notifier);
    await controller.refresh();
    final homepageFuture = controller.loadHomepageMarkdown(
      'https://carol.awiki.ai',
    );

    gateway.myProfile = serverProfile.copyWith(
      nickName: 'Carol New',
      bio: 'Updated bio',
    );
    await controller.refresh();
    homepageCompleter.complete(remoteMarkdown);
    await homepageFuture;

    final profile = container.read(profileProvider).profile;
    expect(profile?.nickName, 'Carol New');
    expect(profile?.bio, 'Updated bio');
    expect(profile?.profileMarkdown, '# Carol');
    expect(controller.visibleProfileContent(), remoteMarkdown);
  });

  test('忽略主页 HTML 响应，避免覆盖已有 profile markdown', () async {
    const serverProfile = UserProfile(
      did: 'did:test:dana',
      nickName: 'Dana',
      bio: 'Initial bio',
      tags: <String>[],
      profileMarkdown: '# Dana\n\n# 如何与我通信\n\nKeep this copy',
      handle: 'dana',
    );
    final gateway = FakeAwikiGateway()..myProfile = serverProfile;
    final container = ProviderContainer(
      overrides: <Override>[
        awikiGatewayProvider.overrideWithValue(gateway),
        profileApplicationServiceProvider.overrideWithValue(
          FakeProfileApplicationService(gateway),
        ),
        profileHomepageResolverProvider.overrideWithValue(
          ProfileHomepageResolver(
            environment: AwikiEnvironmentConfig(baseUrl: 'https://awiki.ai'),
          ),
        ),
        homepageMarkdownLoaderProvider.overrideWithValue(
          (_) async => '<!doctype html><html><body></body></html>',
        ),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(profileProvider.notifier);
    await controller.refresh();
    await controller.loadHomepageMarkdown('https://dana.awiki.ai');

    expect(
      container.read(profileProvider).profile?.profileMarkdown,
      serverProfile.profileMarkdown,
    );
    expect(controller.visibleProfileContent(), serverProfile.profileMarkdown);
  });
}
