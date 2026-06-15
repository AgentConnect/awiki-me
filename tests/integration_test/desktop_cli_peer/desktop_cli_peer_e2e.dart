library desktop_cli_peer_e2e;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/conversation_service.dart';
import 'package:awiki_me/src/application/group_application_service.dart';
import 'package:awiki_me/src/application/messaging_service.dart';
import 'package:awiki_me/src/application/models/attachment_models.dart';
import 'package:awiki_me/src/application/models/app_session.dart';
import 'package:awiki_me/src/application/models/app_thread_ref.dart';
import 'package:awiki_me/src/application/onboarding_service.dart';
import 'package:awiki_me/src/application/ports/relationship_core_port.dart';
import 'package:awiki_me/src/application/relationship_application_service.dart';
import 'package:awiki_me/src/domain/entities/chat_mention.dart';
import 'package:awiki_me/src/domain/entities/chat_message.dart';
import 'package:awiki_me/src/domain/entities/group_member_summary.dart';
import 'package:awiki_me/src/domain/entities/relationship_summary.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

part 'flows/attachment_flow.dart';
part 'flows/contact_flow.dart';
part 'flows/direct_message_flow.dart';
part 'flows/group_message_flow.dart';
part 'support/cli_peer_process.dart';
part 'support/config.dart';
part 'support/polling.dart';

const bool _e2eEnabled = bool.fromEnvironment('AWIKI_E2E');
const String _runId = String.fromEnvironment('AWIKI_E2E_RUN_ID');
const String _platform = String.fromEnvironment('AWIKI_E2E_PLATFORM');
const String _caseName = String.fromEnvironment(
  'AWIKI_E2E_CASE',
  defaultValue: 'full',
);
const String _appHandle = String.fromEnvironment('AWIKI_E2E_APP_HANDLE');
const String _cliHandle = String.fromEnvironment('AWIKI_E2E_CLI_HANDLE');
const String _otpPhone = String.fromEnvironment('DEV_OTP_PHONE');
const String _otpCode = String.fromEnvironment('DEV_OTP_CODE');
const String _cliBin = String.fromEnvironment('AWIKI_CLI_BIN');
const String _cliWorkspace = String.fromEnvironment(
  'AWIKI_CLI_WORKSPACE_HOME_DIR',
);
const String _cliHome = String.fromEnvironment('AWIKI_CLI_HOME_DIR');

enum DesktopCliPeerIntegrationCase {
  full,
  direct,
  group,
  attachment,
  contacts;

  static DesktopCliPeerIntegrationCase parse(String value) {
    return switch (value.trim().toLowerCase()) {
      '' || 'full' => DesktopCliPeerIntegrationCase.full,
      'direct' ||
      'dm' ||
      'message' ||
      'messages' ||
      'direct-only' => DesktopCliPeerIntegrationCase.direct,
      'group' ||
      'groups' ||
      'group-only' => DesktopCliPeerIntegrationCase.group,
      'attachment' ||
      'attachments' ||
      'file' ||
      'files' ||
      'attachment-only' => DesktopCliPeerIntegrationCase.attachment,
      'contact' ||
      'contacts' ||
      'people' ||
      'follow' ||
      'contact-only' => DesktopCliPeerIntegrationCase.contacts,
      _ => throw StateError(
        'Unsupported AWIKI_E2E_CASE "$value". '
        'Use full, direct, group, attachment, or contacts.',
      ),
    };
  }

  bool get runsDirectText =>
      this == DesktopCliPeerIntegrationCase.full ||
      this == DesktopCliPeerIntegrationCase.direct;

  bool get runsGroup =>
      this == DesktopCliPeerIntegrationCase.full ||
      this == DesktopCliPeerIntegrationCase.group;

  bool get runsAttachment =>
      this == DesktopCliPeerIntegrationCase.full ||
      this == DesktopCliPeerIntegrationCase.attachment;

  bool get runsContacts =>
      this == DesktopCliPeerIntegrationCase.full ||
      this == DesktopCliPeerIntegrationCase.contacts;
}

DesktopCliPeerIntegrationCase desktopCliPeerCaseFromEnvironment() =>
    DesktopCliPeerIntegrationCase.parse(_caseName);

void runDesktopCliPeerE2e({
  required DesktopCliPeerIntegrationCase selectedCase,
  String description =
      'Desktop App and CLI peer cover direct, group, and attachment basics',
}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    description,
    (tester) async {
      final config = _DesktopCliPeerSmokeConfig.fromEnvironment();
      final bootstrap = await AppBootstrap.create();
      addTearDown(() async {
        await bootstrap.appSessionService?.logout();
      });

      await tester.pumpWidget(AwikiMeApp(bootstrap: bootstrap));
      await tester.pumpAndSettle();
      expect(find.byType(AppShell), findsOneWidget);

      final session = await _prepareAppIdentity(
        bootstrap.onboardingService!,
        config,
      );
      expect(session.authenticated, isTrue);

      await tester.pumpAndSettle();

      final messaging = bootstrap.messagingService!;
      final messageNonce = _messageNonce();
      final directThread = AppThreadRef.direct(config.cliHandle);

      if (selectedCase.runsDirectText) {
        final conversations = bootstrap.conversationService!;
        await _verifyDirectTextRegression(
          messaging: messaging,
          conversations: conversations,
          thread: directThread,
          ownerDid: session.did,
          config: config,
          nonce: messageNonce,
        );
      }

      if (selectedCase.runsContacts) {
        final relationships = bootstrap.relationshipApplicationService!;
        await _verifyContactRegression(
          relationships: relationships,
          config: config,
        );
      }

      if (selectedCase.runsGroup) {
        final groups = bootstrap.groupApplicationService!;
        await _verifyGroupTextRegression(
          groups: groups,
          messaging: messaging,
          config: config,
          nonce: messageNonce,
        );
      }

      if (selectedCase.runsAttachment) {
        await _verifyAttachmentRegression(
          messaging: messaging,
          thread: directThread,
          config: config,
          nonce: messageNonce,
        );
      }
    },
    skip: !_e2eEnabled,
    timeout: const Timeout(Duration(minutes: 12)),
  );
}

Future<AppSession> _prepareAppIdentity(
  OnboardingService onboarding,
  _DesktopCliPeerSmokeConfig config,
) async {
  final recover = await _tryAppIdentityAction(
    () => onboarding.recoverHandle(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
    ),
  );
  if (recover.session != null) {
    return recover.session!;
  }
  if (!_looksRecoverableForRegister(recover.errorText)) {
    throw StateError(
      'App recover failed and did not look like a missing-handle error: '
      '${_sanitizeDiagnostic(recover.errorText)}',
    );
  }

  final register = await _tryAppIdentityAction(
    () => onboarding.registerHandleWithPhone(
      phone: config.otpPhone,
      otp: config.otpCode,
      handle: config.appHandle,
      nickName: 'AWiki E2E ${config.runId}',
    ),
  );
  if (register.session != null) {
    return register.session!;
  }
  throw StateError(
    'App register failed: ${_sanitizeDiagnostic(register.errorText)}',
  );
}

Future<_AppIdentityAttempt> _tryAppIdentityAction(
  Future<AppSession> Function() action,
) async {
  try {
    return _AppIdentityAttempt.session(await action());
  } on Object catch (error) {
    return _AppIdentityAttempt.error(error.toString());
  }
}
