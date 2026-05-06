import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('登录 tab 展示导入身份凭证并触发导入动作', (tester) async {
    final gateway = FakeAwikiGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    expect(find.text('导入身份凭证'), findsOneWidget);

    await tester.tap(find.text('导入身份凭证'));
    await tester.pump();

    expect(gateway.importCalls, 1);
  });

  testWidgets('登录 tab 点击已保存凭证卡片空白区域也能登录', (tester) async {
    final gateway = FakeAwikiGateway();
    const session = SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );
    gateway.localCredentials = const <SessionIdentity>[session];
    gateway.loginResult = session;
    gateway.myProfile = const UserProfile(
      did: 'did:test:123',
      nickName: 'Alice',
      bio: '',
      profileMarkdown: '',
      tags: <String>[],
    );

    await tester.pumpWidget(
      buildLocalizedTestApp(home: const OnboardingPage(), gateway: gateway),
    );
    await tester.pump();

    final tileRect = tester.getRect(find.byType(AppListTile).first);
    await tester.tapAt(Offset(tileRect.left + 20, tileRect.center.dy));
    await tester.pumpAndSettle();

    expect(gateway.loginCalls, 1);
    expect(gateway.lastLoginCredentialName, 'default');
  });
}
