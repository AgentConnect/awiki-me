import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/settings/settings_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('设置页展示导出身份凭证并触发导出动作', (tester) async {
    final controller = RecordingAppController(
      gateway: FakeAwikiGateway(),
      realtimeGateway: FakeRealtimeGateway(),
      notificationFacade: FakeNotificationFacade(),
      e2eeFacade: FakeE2eeFacade(),
    );
    controller.session = const SessionIdentity(
      did: 'did:test:123',
      credentialName: 'default',
      displayName: 'Alice',
      handle: 'alice',
      jwtToken: 'token-123',
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: SettingsPage(controller: controller),
      ),
    );

    expect(find.text('导出身份凭证'), findsOneWidget);

    await tester.tap(find.text('导出身份凭证'));
    await tester.pump();

    expect(controller.exportCalls, 1);
  });
}
