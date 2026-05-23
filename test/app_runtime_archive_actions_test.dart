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
          ...fakeApplicationServiceOverrides(gateway),
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

    test('导入本地凭证首轮明确标记不支持', () async {
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

      expect(gateway.importCalls, 0);
      expect(container.read(sessionProvider).localCredentials, isEmpty);
      final feedback = container.read(uiFeedbackProvider);
      expect(feedback?.danger, isTrue);
      expect(feedback?.message.id, 'raw');
      expect(
        feedback?.message.detail,
        'IM Core local credential import is not available yet',
      );
    });

    test('导出本地凭证首轮明确标记不支持', () async {
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

      expect(gateway.exportCalls, 0);
      expect(container.read(uiFeedbackProvider)?.danger, isTrue);
      expect(container.read(uiFeedbackProvider)?.message.id, 'raw');
      expect(
        container.read(uiFeedbackProvider)?.message.detail,
        'IM Core local credential export is not available yet',
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
