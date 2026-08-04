import 'package:awiki_me/l10n/app_localizations.dart';
import 'package:awiki_me/src/application/tenant/app_tenant.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/conversation_summary.dart';
import 'package:awiki_me/src/presentation/app_shell/foreground_message_banner.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/foreground_message_banner_provider.dart';
import 'package:awiki_me/src/presentation/shared/awiki_me_design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

const _testFontFamily = 'AwikiBannerGolden';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final data = await rootBundle.load('assets/fonts/awiki_golden_cjk.ttf');
    await (FontLoader(_testFontFamily)..addFont(Future.value(data))).load();
  });

  test('group content uses authoritative title, sender, and preview', () {
    final content = resolveForegroundMessageBannerContent(
      message: _message(groupId: 'group-1'),
      conversation: _conversation(
        displayName: 'new group',
        isGroup: true,
        groupId: 'group-1',
      ),
      senderLabel: 'newhandle1',
      preview: '666',
      groupFallbackTitle: '群聊',
    );

    expect(content.conversationTitle, 'new group');
    expect(content.senderLabel, 'newhandle1');
    expect(content.preview, '666');
    expect(content.isGroup, isTrue);
  });

  test('group content never exposes opaque DID or group identifier', () {
    for (final title in <String>[
      'did:wba:agent-connect.cn:group:group-1',
      'group:group-1',
      'group-1',
    ]) {
      final content = resolveForegroundMessageBannerContent(
        message: _message(groupId: 'group-1'),
        conversation: _conversation(
          displayName: title,
          isGroup: true,
          groupId: 'group-1',
          canonicalGroupDid: 'did:wba:agent-connect.cn:group:group-1',
        ),
        senderLabel: 'newhandle1',
        preview: '666',
        groupFallbackTitle: '群聊',
      );

      expect(content.conversationTitle, '群聊');
      expect(content.conversationTitle, isNot(contains('did:')));
    }
  });

  test('system, control, and opaque encrypted messages are ineligible', () {
    expect(
      isOrdinaryMessagePresentationEligible(
        _message(
          payloadJson:
              '{"schema":"awiki.group.system_event.v1","type":"member_added","group_did":"did:test:group","actor_did":"did:test:a","subject_did":"did:test:b"}',
          originalType: 'application/json',
        ),
      ),
      isFalse,
    );
    expect(
      isOrdinaryMessagePresentationEligible(
        _message(
          payloadJson: '{"schema":"awiki.agent.status.v1"}',
          originalType: 'application/json',
        ),
      ),
      isFalse,
    );
    expect(
      isOrdinaryMessagePresentationEligible(
        _message(
          groupId: 'group-1',
          isEncrypted: true,
          originalType: 'application/awiki-group-e2ee+json',
        ),
      ),
      isFalse,
    );
  });

  test('controller replaces the visible event and fences stale dismissal', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(foregroundMessageBannerProvider.notifier);
    final content = resolveForegroundMessageBannerContent(
      message: _message(),
      conversation: _conversation(displayName: 'Peer'),
      senderLabel: 'Peer',
      preview: 'first',
      groupFallbackTitle: 'Group chat',
    );

    controller.show(
      storageScopeId: _storageScopeId,
      ownerDid: 'did:test:me',
      sessionGeneration: 1,
      conversationId: 'dm:1',
      content: content,
    );
    final firstSequence = container
        .read(foregroundMessageBannerProvider)!
        .sequence;
    controller.show(
      storageScopeId: _storageScopeId,
      ownerDid: 'did:test:me',
      sessionGeneration: 1,
      conversationId: 'dm:1',
      content: ForegroundMessageBannerContent(
        conversationTitle: content.conversationTitle,
        senderLabel: content.senderLabel,
        preview: 'second',
        isGroup: content.isGroup,
        avatarSeed: content.avatarSeed,
      ),
    );

    expect(
      container.read(foregroundMessageBannerProvider)!.content.preview,
      'second',
    );
    controller.dismiss(sequence: firstSequence);
    expect(container.read(foregroundMessageBannerProvider), isNotNull);
    controller.dismiss(
      sequence: container.read(foregroundMessageBannerProvider)!.sequence,
    );
    expect(container.read(foregroundMessageBannerProvider), isNull);
  });

  testWidgets('selected banner renders, taps, swipes, and auto-dismisses', (
    tester,
  ) async {
    var taps = 0;
    var dismissals = 0;
    await _pumpBanner(
      tester,
      event: _event(sequence: 1),
      onTap: () => taps += 1,
      onDismiss: () => dismissals += 1,
    );

    expect(find.text('new group'), findsOneWidget);
    expect(find.text('newhandle1：666'), findsOneWidget);
    expect(find.text('群'), findsOneWidget);
    expect(find.text('刚刚'), findsOneWidget);

    await tester.tap(find.byKey(const Key('foreground-message-banner-card')));
    expect(taps, 1);

    await tester.drag(
      find.byKey(const Key('foreground-message-banner-card')),
      const Offset(0, -80),
    );
    await tester.pump();
    expect(dismissals, 1);

    await _pumpBanner(
      tester,
      event: _event(sequence: 2),
      onTap: () {},
      onDismiss: () => dismissals += 1,
    );
    await tester.pump(foregroundMessageBannerDuration);
    expect(dismissals, 2);
  });

  testWidgets('replacement restarts the four-second dismissal window', (
    tester,
  ) async {
    final event = ValueNotifier<ForegroundMessageBannerEvent>(_event());
    addTearDown(event.dispose);
    var dismissals = 0;

    await tester.pumpWidget(
      _BannerTestApp(
        child: ValueListenableBuilder<ForegroundMessageBannerEvent>(
          valueListenable: event,
          builder: (context, current, _) => ForegroundMessageBanner(
            event: current,
            onTap: () {},
            onDismiss: () => dismissals += 1,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    event.value = _event(sequence: 2, preview: 'replacement');
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(dismissals, 0);
    expect(find.text('newhandle1：replacement'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(dismissals, 1);
  });
}

Future<void> _pumpBanner(
  WidgetTester tester, {
  required ForegroundMessageBannerEvent event,
  required VoidCallback onTap,
  required VoidCallback onDismiss,
}) {
  return tester.pumpWidget(
    _BannerTestApp(
      child: ForegroundMessageBanner(
        event: event,
        onTap: onTap,
        onDismiss: onDismiss,
      ),
    ),
  );
}

class _BannerTestApp extends StatelessWidget {
  const _BannerTestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final platformTheme = AwikiMeTheme.forPlatform(
      TargetPlatform.android,
      fontFamilyOverride: _testFontFamily,
    );
    return CupertinoApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: platformTheme.cupertinoTheme,
      home: CupertinoPageScaffold(
        child: Center(child: SizedBox(width: 366, child: child)),
      ),
    );
  }
}

StorageScopeId get _storageScopeId =>
    StorageScopeId.parse('11111111-1111-4111-8111-111111111111');

ForegroundMessageBannerEvent _event({
  int sequence = 1,
  String preview = '666',
}) {
  return ForegroundMessageBannerEvent(
    sequence: sequence,
    storageScopeId: _storageScopeId,
    ownerDid: 'did:test:me',
    sessionGeneration: 1,
    conversationId: 'group:group-1',
    content: ForegroundMessageBannerContent(
      conversationTitle: 'new group',
      senderLabel: 'newhandle1',
      preview: preview,
      isGroup: true,
      avatarSeed: 'new group',
    ),
    receivedAt: DateTime.utc(2026, 8, 4, 17, 45),
  );
}

ChatMessage _message({
  String? groupId,
  String? payloadJson,
  String originalType = 'text',
  bool isEncrypted = false,
}) {
  return ChatMessage(
    localId: 'message-1',
    remoteId: 'message-1',
    conversationId: groupId == null ? 'dm:1' : 'group:$groupId',
    threadId: groupId == null ? 'dm:1' : 'group:$groupId',
    senderDid: 'did:test:peer',
    senderName: 'newhandle1',
    receiverDid: 'did:test:me',
    groupId: groupId,
    content: '666',
    originalType: originalType,
    createdAt: DateTime.utc(2026, 8, 4, 17, 45),
    isMine: false,
    isEncrypted: isEncrypted,
    sendState: MessageSendState.sent,
    payloadJson: payloadJson,
  );
}

ConversationSummary _conversation({
  required String displayName,
  bool isGroup = false,
  String? groupId,
  String? canonicalGroupDid,
}) {
  return ConversationSummary(
    conversationId: isGroup ? 'group:$groupId' : 'dm:1',
    threadId: isGroup ? 'group:$groupId' : 'dm:1',
    displayName: displayName,
    lastMessagePreview: '666',
    lastMessageAt: DateTime.utc(2026, 8, 4, 17, 45),
    unreadCount: 1,
    isGroup: isGroup,
    groupId: groupId,
    canonicalGroupDid: canonicalGroupDid,
  );
}
