import 'dart:typed_data';
import 'package:awiki_me/src/app/app_services.dart';
import 'package:awiki_me/src/application/account_state_sync_request_bus.dart';
import 'package:awiki_me/src/data/services/awiki_onboarding_utility_client.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:awiki_me/src/application/ports/agent_avatar_port.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_avatar.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_summary.dart';
import 'package:awiki_me/src/domain/entities/agent/agent_status.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/presentation/agents/agent_avatar_editor.dart';
import '../test_support.dart';

const current = AgentAvatar(
  agentId: 'stable-id',
  source: 'preset',
  posterUri: '/avatars/presets/legal.png',
  animatedUri: '/avatars/presets/legal.gif',
  version: '4',
  status: 'ready',
);
const agent = AgentSummary(
  agentDid: 'did:example:agent',
  kind: AgentKind.runtime,
  displayName: 'Helper',
  activeState: 'active',
  latest: AgentLatestStatus(status: 'ready'),
  avatar: current,
);

class Avatars implements AgentAvatarPort {
  bool failSave = false;
  bool failLoad = false;
  bool generation = false;
  bool conflict = false;
  String version = '4';
  final requests =
      <({String id, String version, String action, String? preset})>[];
  @override
  Future<AgentAvatarCapabilities> loadAgentAvatar(String agentDid) async {
    if (failLoad) throw StateError('load');
    return AgentAvatarCapabilities(
      avatar: AgentAvatar.fromJson({...current.toJson(), 'version': version}),
      defaultAvatar: current,
      presetCatalog: const [
        AgentAvatarPreset(
          id: 'financing',
          displayName: '服务器预设',
          posterUri: 'https://foreign.example/new.png',
          animatedUri: 'https://foreign.example/new.gif',
        ),
      ],
      uploadEnabled: true,
      generationEnabled: generation,
    );
  }

  @override
  Future<AgentAvatarMutation> setAgentAvatar({
    required String agentDid,
    required String requestId,
    required String expectedVersion,
    required String action,
    String? presetId,
    Uint8List? image,
    String? name,
    String? responsibility,
    String? imageDescription,
  }) async {
    requests.add((
      id: requestId,
      version: expectedVersion,
      action: action,
      preset: presetId,
    ));
    if (conflict) {
      version = '5';
      throw const AwikiOnboardingUtilityError(
        message: 'agent_avatar.version_conflict',
      );
    }
    if (failSave) throw StateError('save');
    return AgentAvatarMutation(
      avatar: AgentAvatar.fromJson({...current.toJson(), 'version': '5'}),
      inventoryVersion: '5',
    );
  }
}

Future<void> open(
  WidgetTester tester,
  Avatars avatars, {
  AccountStateSyncRequestBus? bus,
}) async {
  await tester.pumpWidget(
    buildLocalizedTestApp(
      session: const SessionIdentity(
        did: 'did:example:owner',
        credentialName: 'owner',
        displayName: 'Owner',
      ),
      providerOverrides: [
        agentAvatarPortProvider.overrideWithValue(avatars),
        if (bus != null)
          accountStateSyncRequestBusProvider.overrideWithValue(bus),
      ],
      home: Builder(
        builder: (context) => CupertinoButton(
          onPressed: () => showAgentAvatarEditor(context, agent),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancel after choosing preset never writes', (tester) async {
    final avatars = Avatars();
    await open(tester, avatars);
    expect(find.byKey(const Key('agent-avatar-generate')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const Key('agent-avatar-preset-financing')),
    );
    await tester.tap(find.byKey(const Key('agent-avatar-preset-financing')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent-avatar-cancel')));
    await tester.pumpAndSettle();
    expect(avatars.requests, isEmpty);
    expect(find.byType(AgentAvatarEditor), findsNothing);
  });

  testWidgets('save failure preserves draft and request for safe retry', (
    tester,
  ) async {
    final avatars = Avatars()..failSave = true;
    await open(tester, avatars);
    await tester.ensureVisible(
      find.byKey(const Key('agent-avatar-preset-financing')),
    );
    await tester.tap(find.byKey(const Key('agent-avatar-preset-financing')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('agent-avatar-save')));
    await tester.pumpAndSettle();
    expect(find.byType(AgentAvatarEditor), findsOneWidget);
    final first = avatars.requests.single;
    avatars.failSave = false;
    await tester.tap(find.byKey(const Key('agent-avatar-save')));
    await tester.pumpAndSettle();
    expect(avatars.requests.last, first);
    expect(first.action, 'preset');
    expect(first.preset, 'financing');
    expect(first.version, '4');
    expect(find.byType(AgentAvatarEditor), findsNothing);
  });

  testWidgets(
    'load failure exposes retry and reset is an explicit saved action',
    (tester) async {
      final avatars = Avatars()..failLoad = true;
      await open(tester, avatars);
      expect(find.byKey(const Key('agent-avatar-reset')), findsNothing);
      avatars.failLoad = false;
      await tester.tap(find.byKey(const Key('agent-avatar-retry-load')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('agent-avatar-reset')));
      await tester.tap(find.byKey(const Key('agent-avatar-reset')));
      await tester.pump();
      expect(avatars.requests, isEmpty);
      await tester.tap(find.byKey(const Key('agent-avatar-save')));
      await tester.pumpAndSettle();
      expect(avatars.requests.single.action, 'reset');
      expect(avatars.requests.single.preset, isNull);
    },
  );
  testWidgets(
    'conflict preserves selection and requires explicit save with new version',
    (tester) async {
      final avatars = Avatars()..conflict = true;
      await open(tester, avatars);
      expect(find.text('服务器预设'), findsOneWidget);
      await tester.tap(find.byKey(const Key('agent-avatar-preset-financing')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('agent-avatar-save')));
      await tester.pumpAndSettle();
      expect(find.byType(AgentAvatarEditor), findsOneWidget);
      final first = avatars.requests.single;
      avatars.conflict = false;
      await tester.tap(find.byKey(const Key('agent-avatar-save')));
      await tester.pumpAndSettle();
      expect(avatars.requests.last.version, '5');
      expect(avatars.requests.last.preset, first.preset);
      expect(avatars.requests.last.id, isNot(first.id));
    },
  );

  testWidgets(
    'committed avatar with failed refresh cannot be submitted twice',
    (tester) async {
      final avatars = Avatars();
      final bus = AccountStateSyncRequestBus()
        ..attach((reason, {force = false, minimumVersion}) async {
          throw StateError('refresh failed');
        });
      await open(tester, avatars, bus: bus);
      await tester.tap(find.byKey(const Key('agent-avatar-preset-financing')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('agent-avatar-save')));
      await tester.pumpAndSettle();
      expect(find.byType(AgentAvatarEditor), findsOneWidget);
      expect(avatars.requests, hasLength(1));
      expect(
        tester
            .widget<CupertinoButton>(find.byKey(const Key('agent-avatar-save')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('agent-avatar-cancel')));
      await tester.pumpAndSettle();
      expect(avatars.requests, hasLength(1));
    },
  );
  testWidgets(
    'a new draft after committed refresh failure uses the committed version',
    (tester) async {
      final avatars = Avatars();
      final bus = AccountStateSyncRequestBus()
        ..attach((reason, {force = false, minimumVersion}) async {
          throw StateError('refresh');
        });
      await open(tester, avatars, bus: bus);
      await tester.tap(find.byKey(const Key('agent-avatar-preset-financing')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('agent-avatar-save')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('agent-avatar-reset')));
      await tester.tap(find.byKey(const Key('agent-avatar-reset')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('agent-avatar-save')));
      await tester.pumpAndSettle();
      expect(avatars.requests.last.version, '5');
      expect(avatars.requests.last.id, isNot(avatars.requests.first.id));
    },
  );
}
