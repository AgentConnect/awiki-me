import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/entities/user_profile.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_lifecycle_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/app_runtime_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/foreground_message_banner_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/selected_conversation_provider.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  testWidgets('AppShell banner tap opens the committed conversation', (
    tester,
  ) async {
    const session = SessionIdentity(
      did: 'did:test:me',
      credentialName: 'default',
      displayName: 'Me',
      handle: 'me',
      jwtToken: 'token',
    );
    final conversation = ConversationSummary(
      conversationId: 'group:group-1',
      threadId: 'group:group-1',
      displayName: 'new group',
      lastMessagePreview: '666',
      lastMessageAt: DateTime(2026, 8, 4, 17, 45),
      unreadCount: 1,
      isGroup: true,
      groupId: 'group-1',
    );
    final gateway = FakeAwikiGateway()
      ..myProfile = const UserProfile(
        did: 'did:test:me',
        nickName: 'Me',
        bio: '',
        tags: <String>[],
        profileMarkdown: '',
        handle: 'me',
      )
      ..conversations = <ConversationSummary>[conversation];
    final realtimeGateway = FakeRealtimeGateway();

    await tester.pumpWidget(
      buildLocalizedTestApp(
        home: const AppShell(),
        gateway: gateway,
        realtimeGateway: realtimeGateway,
        session: session,
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
      listen: false,
    );
    await _activateRuntime(container, session);
    await tester.pump();
    container
        .read(appLifecycleProvider.notifier)
        .setLifecycle(AppLifecycleState.resumed);
    final epoch = container.read(sessionProvider).activeEpoch!;
    container
        .read(foregroundMessageBannerProvider.notifier)
        .show(
          storageScopeId: container
              .read(activeAppTenantProvider)
              .storageScopeId,
          ownerDid: epoch.ownerDid,
          sessionGeneration: epoch.generation,
          conversationId: conversation.conversationId,
          content: const ForegroundMessageBannerContent(
            conversationTitle: 'new group',
            senderLabel: 'newhandle1',
            preview: '666',
            isGroup: true,
            avatarSeed: 'new group',
          ),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const Key('foreground-message-banner-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('foreground-message-banner-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('foreground-message-banner-preview')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('foreground-message-banner-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      container.read(selectedConversationProvider),
      conversation.conversationId,
    );
    expect(container.read(foregroundMessageBannerProvider), isNull);
  });
}

Future<void> _activateRuntime(
  ProviderContainer container,
  SessionIdentity session,
) async {
  final committed = await container
      .read(appSessionServiceProvider)
      .activateIdentity(
        AppSession(
          did: session.did,
          identityId: session.credentialName,
          displayName: session.displayName,
          handle: session.handle,
          localAlias: session.credentialName,
          authenticated: session.jwtToken != null,
          jwtToken: session.jwtToken,
          accountBinding: session.accountBinding,
        ),
      );
  await container
      .read(appRuntimeProvider.notifier)
      .activateCommittedSession(committed);
}
