part of '../desktop_cli_peer_e2e.dart';

/// Uses a fresh owned fixture, optionally exchanged by the configured test helper.
Future<void> _verifyAgentAvatarEditing(
  _DesktopAppRobot robot,
  WidgetTester tester,
  _DesktopCliPeerSmokeConfig config,
  AppSession session,
) async {
  robot.failureCaseId = 'AGENT-AVATAR-E2E-001';
  final raw =
      jsonDecode(File(_desktopCliPeerRunConfigPath).readAsStringSync()) as Map;
  final command = (raw['agentAvatarFixtureCommand'] as List?)?.cast<String>();
  final created = <String>[];
  final inventory = robot.container.read(agentInventoryPortProvider);
  addTearDown(() async {
    if (command != null && created.isNotEmpty) {
      for (final agentDid in created.reversed) {
        await inventory.removeAgentFromAccount(agentDid: agentDid);
      }
      final remaining = await inventory.listAgents();
      expect(
        remaining.where((agent) => created.contains(agent.agentDid)),
        isEmpty,
      );
      await _runAgentAvatarFixture(command, {
        'action': 'verify_removed',
        'controller_did': session.did,
        'controller_account_id': session.accountId,
        'agent_dids': created.reversed.toList(),
        'scope': config.runId,
      });
    }
  });
  var did = raw['agentAvatarDid'] as String?;
  if ((did == null || did.isEmpty) && command != null) {
    final daemonToken = await inventory.issueDaemonToken(
      controllerDid: session.did,
      controllerHandle:
          session.handle ??
          '${config.appHandle}.${config.environment.didDomain}',
      clientPlatform: config.platform,
    );
    final daemon = await _runAgentAvatarFixture(command, {
      'action': 'exchange',
      'kind': 'daemon',
      'token': daemonToken.token,
      'controller_did': session.did,
      'controller_account_id': session.accountId,
      'scope': config.runId,
    });
    final daemonDid = daemon['did'] as String;
    created.add(daemonDid);
    final handle =
        'st-runtime-${List.generate(12, (_) => math.Random.secure().nextInt(16).toRadixString(16)).join()}';
    final runtimeToken = await inventory.issueRuntimeToken(
      controllerDid: session.did,
      daemonAgentDid: daemonDid,
      runtime: 'system-test',
      handle: handle,
      displayName: 'Avatar E2E',
      preferredLanguage: 'zh',
    );
    final runtime = await _runAgentAvatarFixture(command, {
      'action': 'exchange',
      'kind': 'runtime',
      'token': runtimeToken.token,
      'handle': handle,
      'controller_did': session.did,
      'controller_account_id': session.accountId,
      'scope': config.runId,
    });
    did = runtime['did'] as String;
    created.add(did);
  }
  if (did == null || did.isEmpty) {
    throw StateError(
      'agent-avatars requires AWIKI_E2E_AGENT_AVATAR_DID: a fresh disposable agent owned by accounts.appUser.',
    );
  }
  final port = robot.container.read(agentAvatarPortProvider);
  if (port == null) {
    throw StateError('Production AgentAvatarPort is unavailable.');
  }
  final initial = await port.loadAgentAvatar(did);
  expect(
    initial.avatar.version,
    '0',
    reason: 'Only a fresh disposable fixture may be edited.',
  );
  expect(initial.avatar.source, 'default');
  expect(initial.uploadEnabled, isTrue);
  final originalChooser = FileSelectorPlatform.instance;
  final chooser = _AvatarFixtureChooser();
  final fixtures = await Directory.systemTemp.createTemp(
    'awiki-agent-avatar-e2e-',
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  FileSelectorPlatform.instance = chooser;
  Future<void> tap(String key) =>
      robot.tapOne(find.byKey(Key(key)), description: key);
  Future<void> ready(String key) => robot.pumpUntil(
    description: 'enabled $key',
    condition: () {
      final target = find.byKey(Key(key));
      return target.evaluate().length == 1 &&
          tester.widget<CupertinoButton>(target).onPressed != null;
    },
  );
  Future<void> openEditor() async {
    await tap('agent-action-avatar');
    await ready('agent-avatar-preset-research');
  }

  Future<void> save() async {
    await tap('agent-avatar-save');
    await robot.pumpUntil(
      description: 'agent avatar committed and editor dismissed',
      condition: () => find.byType(AgentAvatarEditor).evaluate().isEmpty,
    );
  }

  Future<List<int>> download(String uri, String contentType) async {
    final response = await (await client.getUrl(Uri.parse(uri))).close();
    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, contentType);
    expect(
      response.headers.value(HttpHeaders.cacheControlHeader),
      contains('immutable'),
    );
    final bytes = await response.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    expect(bytes.length, lessThanOrEqualTo(5 * 1024 * 1024));
    return bytes;
  }

  var changed = false;
  try {
    await robot.container.read(agentsProvider.notifier).load();
    await robot.tapOne(
      find.bySemanticsIdentifier('e2e-agents-tab'),
      description: 'agents tab',
    );
    await robot.pumpUntil(
      description: 'reviewed agent fixture visible',
      condition: () =>
          find.byKey(ValueKey('agent-list-tile-$did')).evaluate().length == 1,
    );
    await tap('agent-list-tile-$did');
    await openEditor();
    final preset = initial.presetCatalog.firstWhere((item) => item.selectable);
    expect(initial.defaultAvatar, isNotNull);
    await tester.ensureVisible(
      find.byKey(Key('agent-avatar-preset-${preset.id}')),
    );
    await tap('agent-avatar-preset-${preset.id}');
    await tap('agent-avatar-cancel');
    expect(
      (await port.loadAgentAvatar(did)).avatar.toJson(),
      initial.avatar.toJson(),
    );
    await openEditor();
    await tester.ensureVisible(
      find.byKey(const Key('agent-avatar-preset-research')),
    );
    await tap('agent-avatar-preset-research');
    changed = true;
    await save();
    final selected = (await port.loadAgentAvatar(did)).avatar;
    expect(selected.agentId, initial.avatar.agentId);
    expect(selected.presetId, preset.id);
    expect(selected.version, '1');
    final gif = img.Image(width: 32, height: 32);
    gif.addFrame(
      img.fill(
        img.Image(width: 32, height: 32),
        color: img.ColorRgb8(0, 128, 255),
      ),
    );
    final file = File('${fixtures.path}/agent.gif');
    await file.writeAsBytes(img.encodeGif(gif));
    chooser.next = XFile(file.path);
    await openEditor();
    await tester.ensureVisible(find.byKey(const Key('agent-avatar-upload')));
    await tap('agent-avatar-upload');
    await ready('agent-avatar-save');
    expect(
      find.byType(Crop),
      findsNothing,
      reason: 'GIF must bypass the static crop path.',
    );
    await save();
    final uploaded = (await port.loadAgentAvatar(did)).avatar;
    expect(uploaded.agentId, initial.avatar.agentId);
    expect(uploaded.source, 'upload');
    final animated = await download(uploaded.animatedUri!, 'image/gif');
    final decoder = img.GifDecoder()..startDecode(Uint8List.fromList(animated));
    expect(decoder.numFrames(), greaterThan(1));
    expect(
      img.decodePng(
        Uint8List.fromList(await download(uploaded.posterUri, 'image/png')),
      ),
      isNotNull,
    );
    await robot.pumpUntil(
      description: 'shared agent avatar appears in the list',
      condition: () => find
          .descendant(
            of: find.byKey(ValueKey('agent-list-tile-$did')),
            matching: find.byType(AgentAvatarImage),
          )
          .evaluate()
          .isNotEmpty,
    );
    final avatar = find
        .descendant(
          of: find.byKey(ValueKey('agent-list-tile-$did')),
          matching: find.byType(AgentAvatarImage),
        )
        .first;
    expect(tester.getSize(avatar).width, tester.getSize(avatar).height);
    await openEditor();
    await tester.ensureVisible(find.byKey(const Key('agent-avatar-reset')));
    await tap('agent-avatar-reset');
    await save();
    final reset = (await port.loadAgentAvatar(did)).avatar;
    expect(reset.agentId, initial.avatar.agentId);
    expect(reset.presetId, initial.avatar.presetId);
    expect(reset.source, 'default');
    expect(int.parse(reset.version), greaterThan(int.parse(uploaded.version)));
    await E2eCaseAttestationWriter.markPassed(
      'AGENT-AVATAR-E2E-001',
      phases: const [
        'cancel_does_not_write_and_preset_persists',
        'gif_frames_and_public_poster_are_preserved',
        'shared_square_avatar_and_reset_keep_stable_id',
      ],
    );
  } finally {
    client.close(force: true);
    FileSelectorPlatform.instance = originalChooser;
    await fixtures.delete(recursive: true);
    if (changed) {
      final current = (await port.loadAgentAvatar(did)).avatar;
      final hex = List.generate(
        32,
        (_) => math.Random.secure().nextInt(16).toRadixString(16),
      ).join();
      await port.setAgentAvatar(
        agentDid: did,
        requestId:
            '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}-8${hex.substring(17, 20)}-${hex.substring(20)}',
        expectedVersion: current.version,
        action: 'reset',
      );
    }
  }
}

Future<Map<String, dynamic>> _runAgentAvatarFixture(
  List<String> command,
  Map<String, Object?> request,
) async {
  if (command.isEmpty) throw StateError('Avatar fixture helper is missing.');
  final process = await Process.start(command.first, command.skip(1).toList());
  final output = process.stdout.transform(utf8.decoder).join();
  final errors = process.stderr.drain<void>();
  process.stdin.write(jsonEncode(request));
  await process.stdin.close();
  final code = await process.exitCode.timeout(
    const Duration(seconds: 60),
    onTimeout: () {
      process.kill();
      throw StateError('Avatar fixture helper timed out.');
    },
  );
  await errors;
  final value = await output;
  if (code != 0 || value.length > 16384) {
    throw StateError(
      'Avatar fixture helper failed (exit $code); inspect its protected local evidence.',
    );
  }
  return jsonDecode(value) as Map<String, dynamic>;
}
