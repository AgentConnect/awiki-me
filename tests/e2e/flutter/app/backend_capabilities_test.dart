// Real normal AppBootstrap + native Core against the task-only Open Server.
// No authentication/provider result is injected; every identity is registered.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/app/awiki_me_app.dart';
import 'package:awiki_me/src/app/bootstrap.dart';
import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
import 'package:awiki_me/src/application/tenant/builtin_tenant_config.dart';
import 'package:awiki_me/src/data/services/method_channel_desktop_startup_presentation_service.dart';
import 'package:awiki_me/src/l10n/l10n.dart';
import 'package:awiki_me/src/presentation/app_shell/app_shell.dart';
import 'package:awiki_me/src/presentation/app_shell/providers/session_provider.dart';
import 'package:awiki_me/src/presentation/chat/chat_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_page.dart';
import 'package:awiki_me/src/presentation/onboarding/onboarding_provider.dart';
import 'package:awiki_me/src/presentation/server_features/backend_capabilities_provider.dart';
import 'package:awiki_me/src/presentation/shared/widgets/app_widgets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Open Server native registration and plaintext round trip', (
    tester,
  ) async {
    const fixturePath = String.fromEnvironment('AWIKI_CAPABILITY_FIXTURE');
    final file = File(fixturePath);
    expect(
      await FileSystemEntity.type(fixturePath, followLinks: false),
      FileSystemEntityType.file,
    );
    final stat = await file.stat();
    expect(stat.type, FileSystemEntityType.file);
    expect(stat.mode & 0x3f, 0, reason: 'Fixture must be private');
    final fixture =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final root = Directory(fixture['runRoot'] as String);
    expect(await root.exists(), isFalse, reason: 'Fresh automatic state only');
    await root.create(recursive: true);
    const origin = 'https://openserver-adapt.anpclaw.com';
    expect(fixture['origin'], origin);
    final key = base64Encode(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    final cliEnv = <String, String>{
      ...Platform.environment,
      'AWIKI_CLI_WORKSPACE_HOME_DIR': '${root.path}/cli',
      'AWIKI_IM_CORE_VAULT_ROOT_KEY_B64': key,
    };
    Future<Map<String, dynamic>> cli(List<String> args) async {
      final result = await Process.run(
        fixture['cli'] as String,
        args,
        environment: cliEnv,
      );
      expect(
        result.exitCode,
        0,
        reason: 'Candidate CLI ${args.take(2).join(' ')}',
      );
      final body = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(body['ok'], isTrue);
      return body['data'] as Map<String, dynamic>;
    }

    await initializeBuiltinTenantCatalog();
    final bootstrap = await AppBootstrap.create(
      environment: AwikiEnvironmentConfig(
        baseUrl: origin,
        userServiceUrl: origin,
        didDomain: 'openserver-adapt.anpclaw.com',
        messageServiceUrl: origin,
        mailServiceUrl: origin,
        anpServiceUrl: '$origin/anp-im/rpc',
        anpServiceDid: 'did:wba:openserver-adapt.anpclaw.com',
      ),
      appStateRoot: '${root.path}/app',
    );
    const capture = Key('capability-native-capture');
    try {
      await tester.binding.setSurfaceSize(const Size(1200, 860));
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: AwikiMeApp(
            bootstrap: bootstrap,
            providerOverrides: [
              desktopStartupPresentationServiceProvider.overrideWithValue(
                buildDesktopStartupPresentationService(),
              ),
            ],
          ),
        ),
      );
      await until(
        tester,
        () => find.byType(OnboardingPage).evaluate().isNotEmpty,
        'onboarding',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(OnboardingPage)),
      );
      await until(
        tester,
        () => container.read(onboardingProvider).serverInfo != null,
        'public discovery',
      );
      final labels = tester.element(find.byType(OnboardingPage)).l10n;
      expect(find.bySemanticsIdentifier('e2e-phone-input'), findsNothing);
      final handle = 'adaptapp${DateTime.now().millisecondsSinceEpoch}';
      final field = find.descendant(
        of: find.bySemanticsIdentifier('e2e-handle-input'),
        matching: find.byType(CupertinoTextField),
      );
      await tester.enterText(field, handle);
      await captureImage(tester, capture, root, 'registration');
      await tester.tap(find.text(labels.onboardingCompleteRegister));
      await until(
        tester,
        () => find.byType(AppShell).evaluate().isNotEmpty,
        'registered app shell',
      );
      await until(
        tester,
        () =>
            container
                .read(backendFeaturesProvider)
                .valueOrNull
                ?.supports('direct') ==
            true,
        'authenticated discovery',
      );
      expect(
        container
            .read(backendFeaturesProvider)
            .valueOrNull
            ?.support('direct_e2ee'),
        'unsupported',
      );
      expect(find.byKey(const Key('desktop-rail-agents')), findsNothing);
      final appDid = container.read(sessionProvider).session!.did;
      await cli([
        'tenant',
        'setup',
        'candidate',
        '--backend-base-url',
        origin,
        '--did-host',
        'openserver-adapt.anpclaw.com',
      ]);
      await cli([
        'id',
        'register',
        '--handle',
        '${handle}peer',
        '--handle-only',
      ]);
      await cli([
        'msg',
        'send',
        '--to',
        appDid,
        '--text',
        'native capability inbound',
        '--secure',
        'off',
      ]);
      await until(
        tester,
        () => find.text('native capability inbound').evaluate().isNotEmpty,
        'ordinary inbound message',
      );
      await tester.tap(find.text('native capability inbound').first);
      await until(
        tester,
        () => find.byType(ChatView).evaluate().isNotEmpty,
        'chat view',
      );
      final security = tester.widget<AppIconButton>(
        find.byKey(const Key('chat-message-security')),
      );
      expect(security.onPressed, isNull);
      expect(
        security.semanticLabel,
        contains(labels.serverFeaturesUnsupported),
      );
      final input = find.descendant(
        of: find.byType(ChatView),
        matching: find.byType(CupertinoTextField),
      );
      await tester.enterText(input, 'native capability outbound');
      await tester.pump();
      expect(
        tester
            .widget<AppPressable>(find.byKey(const Key('chat-send-button')))
            .enabled,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('chat-send-button')));
      await until(
        tester,
        () => tester.widget<CupertinoTextField>(input).controller!.text.isEmpty,
        'submitted draft cleared',
      );
      var received = false;
      for (var attempt = 0; attempt < 15 && !received; attempt++) {
        await tester.pump(const Duration(seconds: 1));
        final inbox = await cli(['msg', 'inbox', '--limit', '20']);
        received = jsonEncode(inbox).contains('native capability outbound');
      }
      await captureImage(tester, capture, root, 'outbound-result');
      expect(
        received,
        isTrue,
        reason: 'Independent CLI must receive the outbound message',
      );
      await captureImage(tester, capture, root, 'ordinary-chat');
      await tester.tap(find.byKey(const Key('desktop-rail-settings')));
      await until(
        tester,
        () => find
            .byKey(const Key('settings-server-features-row'))
            .evaluate()
            .isNotEmpty,
        'settings',
      );
      await tester.tap(find.byKey(const Key('settings-server-features-row')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(labels.serverFeaturesTitle), findsWidgets);
      await captureImage(tester, capture, root, 'server-features');
      await File('${root.path}/result.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'origin': origin,
          'normal_registration': true,
          'plaintext_round_trip': true,
          'encryption_selector_disabled': true,
          'automatic_state': 'retained',
          'manual_state': 'untouched',
        }),
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await bootstrap.dispose();
      await tester.binding.setSurfaceSize(null);
    }
  });
}

Future<void> until(
  WidgetTester tester,
  bool Function() condition,
  String stage,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(condition(), isTrue, reason: stage);
  debugPrint('Capability E2E stage passed: $stage');
}

Future<void> captureImage(
  WidgetTester tester,
  Key key,
  Directory root,
  String name,
) async {
  await tester.pump();
  final image = await tester
      .renderObject<RenderRepaintBoundary>(find.byKey(key))
      .toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(
    '${root.path}/$name.png',
  ).writeAsBytes(bytes!.buffer.asUint8List());
  image.dispose();
}
