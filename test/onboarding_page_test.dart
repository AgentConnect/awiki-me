import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('登录 tab 展示导入身份凭证并触发导入动作', (tester) async {
    final controller = RecordingAppController(
      gateway: FakeAwikiGateway(),
      realtimeGateway: FakeRealtimeGateway(),
      notificationFacade: FakeNotificationFacade(),
      e2eeFacade: FakeE2eeFacade(),
    );

    await tester.pumpWidget(
      CupertinoApp(
        home: OnboardingPage(controller: controller),
      ),
    );
    await tester.pump();

    expect(find.text('导入身份凭证'), findsOneWidget);

    await tester.tap(find.text('导入身份凭证'));
    await tester.pump();

    expect(controller.importCalls, 1);
  });
}
