import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/profile/peer_profile_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('私聊资料页完整显示 DID 并支持一键复制', (tester) async {
    const longDid =
        'did:awiki:user:cgw-agent-lab:e1_abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789';
    const profile = UserProfile(
      did: longDid,
      nickName: 'CGW Agent',
      bio: '融资协作 Agent',
      tags: <String>['Agent'],
      profileMarkdown: '',
      handle: 'cgw.awiki.ai',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{longDid: profile};
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'Clipboard.setData') {
            final data = methodCall.arguments as Map<Object?, Object?>;
            clipboardText = data['text'] as String?;
          }
          return null;
        });

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PeerProfilePage(did: longDid),
        gateway: gateway,
        homepageMarkdownLoader: (_) async => null,
      ),
    );
    await tester.pumpAndSettle();

    final didFinder = find.byKey(const Key('peer-profile-did-value'));
    expect(didFinder, findsOneWidget);
    final didText = tester.widget<Text>(didFinder);
    expect(didText.data, longDid);
    expect(didText.maxLines, isNull);
    expect(
      find.byKey(const Key('peer-profile-copy-did-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('peer-profile-copy-did-button')));
    await tester.pump();

    expect(clipboardText, longDid);
    expect(find.text('DID 已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  testWidgets('私聊资料页主页链接优先使用 fullHandle', (tester) async {
    const did = 'did:wba:anpclaw.com:zhuocheng:e1_key';
    const profile = UserProfile(
      did: did,
      nickName: 'zhuocheng',
      bio: '',
      tags: <String>[],
      profileMarkdown: '',
      handle: 'zhuocheng',
      fullHandle: 'zhuocheng.anpclaw.com',
    );
    final gateway = FakeAwikiGateway()
      ..publicProfilesByQuery = const <String, UserProfile>{did: profile};
    String? requestedHomepageUrl;

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const PeerProfilePage(did: did),
        gateway: gateway,
        homepageMarkdownLoader: (url) async {
          requestedHomepageUrl = url;
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedHomepageUrl, 'https://zhuocheng.anpclaw.com');
    expect(find.text('https://zhuocheng.anpclaw.com'), findsOneWidget);
  });
}
