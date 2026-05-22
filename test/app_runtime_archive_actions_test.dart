import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/ui_feedback.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  group('AppRuntime archive actions', () {
    late FakeAwikiGateway gateway;
    late ProviderContainer container;

    setUp(() {
      gateway = FakeAwikiGateway();
      container = ProviderContainer(
        overrides: <Override>[
          awikiGatewayProvider.overrideWithValue(gateway),
          awikiAccountGatewayProvider.overrideWithValue(gateway),
          realtimeGatewayProvider.overrideWithValue(FakeRealtimeGateway()),
          notificationFacadeProvider.overrideWithValue(
            FakeNotificationFacade(),
          ),
          e2eeFacadeProvider.overrideWithValue(FakeE2eeFacade()),
          updateServiceProvider.overrideWithValue(FakeUpdateService()),
        ],
      );
      addTearDown(container.dispose);
    });

    test('导入成功后刷新本地凭证列表并写入成功提示', () async {
      gateway.importedCredential = const SessionIdentity(
        did: 'did:test:123',
        credentialName: 'default',
        displayName: 'Alice',
        handle: 'alice',
        jwtToken: 'token-123',
      );
      gateway.localCredentials = <SessionIdentity>[gateway.importedCredential!];

      await container
          .read(appRuntimeProvider.notifier)
          .importCredentialArchive();

      expect(gateway.importCalls, 1);
      expect(gateway.listLocalCredentialsCalls, 1);
      expect(container.read(sessionProvider).localCredentials, hasLength(1));
      expect(
        container.read(uiFeedbackProvider)?.message.id,
        'importSuccessSelectCredential',
      );
    });

    test('导出成功后写入成功提示', () async {
      container
          .read(sessionProvider.notifier)
          .setSession(
            const SessionIdentity(
              did: 'did:test:123',
              credentialName: 'default',
              displayName: 'Alice',
              handle: 'alice',
              jwtToken: 'token-123',
            ),
          );
      gateway.exportedPath = '/tmp/awiki-credential-alice-default.zip';

      await container
          .read(appRuntimeProvider.notifier)
          .exportCurrentCredential();

      expect(gateway.exportCalls, 1);
      expect(container.read(uiFeedbackProvider)?.message.id, 'exportedTo');
      expect(
        container.read(uiFeedbackProvider)?.message.path,
        '/tmp/awiki-credential-alice-default.zip',
      );
    });

    test('重新识别本地凭证会刷新列表并写入反馈', () async {
      gateway.localCredentials = const <SessionIdentity>[
        SessionIdentity(
          did: 'did:test:123',
          credentialName: 'default',
          displayName: 'Alice',
          handle: 'alice',
          jwtToken: 'token-123',
        ),
      ];
      await container.read(appRuntimeProvider.notifier).initialize();
      expect(gateway.listLocalCredentialsCalls, 1);

      gateway.localCredentials = const <SessionIdentity>[
        SessionIdentity(
          did: 'did:test:456',
          credentialName: 'bob',
          displayName: 'Bob',
          handle: 'bob',
          jwtToken: 'token-456',
        ),
      ];

      await container
          .read(appRuntimeProvider.notifier)
          .refreshLocalCredentials();

      expect(gateway.listLocalCredentialsCalls, 2);
      expect(
        container.read(sessionProvider).localCredentials.single.credentialName,
        'bob',
      );
      expect(
        container.read(uiFeedbackProvider)?.message.id,
        'localCredentialsRefreshed',
      );
      expect(container.read(uiFeedbackProvider)?.message.value, '1');
    });
  });
}
