import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('AppController archive actions', () {
    late FakeAwikiGateway gateway;
    late AppController controller;

    setUp(() {
      gateway = FakeAwikiGateway();
      controller = AppController(
        gateway: gateway,
        realtimeGateway: FakeRealtimeGateway(),
        notificationFacade: FakeNotificationFacade(),
        e2eeFacade: FakeE2eeFacade(),
      );
    });

    test('导入成功后刷新本地凭证列表并写入成功提示', () async {
      gateway.importedCredential = const SessionIdentity(
        did: 'did:test:123',
        credentialName: 'default',
        displayName: 'Alice',
        handle: 'alice',
        jwtToken: 'token-123',
      );
      gateway.localCredentials = <SessionIdentity>[
        gateway.importedCredential!,
      ];

      await controller.importCredentialArchive();

      expect(gateway.importCalls, 1);
      expect(gateway.listLocalCredentialsCalls, 1);
      expect(controller.localCredentials, hasLength(1));
      expect(controller.infoMessage, '导入成功，请选择该凭证登录');
    });

    test('导出成功后写入成功提示', () async {
      controller.session = const SessionIdentity(
        did: 'did:test:123',
        credentialName: 'default',
        displayName: 'Alice',
        handle: 'alice',
        jwtToken: 'token-123',
      );
      gateway.exportedPath = '/tmp/awiki-credential-alice-default.zip';

      await controller.exportCurrentCredential();

      expect(gateway.exportCalls, 1);
      expect(
        controller.infoMessage,
        '已导出到 /tmp/awiki-credential-alice-default.zip',
      );
    });
  });
}
