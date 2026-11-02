import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

import '../tests/e2e/flutter/support/hosted_gateway_fixture.dart';
import '../tests/e2e/protected_files.dart';

/// Fixture preparation runs natively on Windows. Only the existing fixed-host
/// OTP operator runs remotely; no App, CLI, Daemon or model runs there.
Future<void> main(List<String> arguments) async {
  HostedGatewayFixture? gateway;
  var phase = 'input';
  try {
    if (!Platform.isWindows ||
        arguments.isEmpty ||
        arguments.length > 2 ||
        (arguments.length == 2 && arguments[1] != '--resume') ||
        !RegExp(
          r'^[A-Za-z0-9][A-Za-z0-9_-]{0,80}$',
        ).hasMatch(arguments.first)) {
      throw StateError('hosted_fixture_windows_run_id_required');
    }
    final root = Directory('.e2e/windows-hosted/${arguments.first}').absolute;
    final resume = arguments.length == 2;
    final intent = File('${root.path}/intent.private.json');
    if (FileSystemEntity.typeSync(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('hosted_fixture_link_rejected');
    }
    if (root.existsSync() && !resume) {
      throw StateError('hosted_fixture_intent_already_exists');
    }
    if (resume && !isPrivateE2eFile(intent)) {
      throw StateError('hosted_fixture_private_intent_required');
    }
    root.createSync(recursive: true);
    protectE2ePathSync(root.path, directory: true);
    final random = Random.secure();
    String nonce(int bytes) => List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final run = nonce(16);
    final operation = nonce(16);
    final freshOperationId =
        '${operation.substring(0, 8)}-${operation.substring(8, 12)}-'
        '4${operation.substring(13, 16)}-a${operation.substring(17, 20)}-${operation.substring(20)}';
    final state = resume
        ? jsonDecode(intent.readAsStringSync()) as Map<String, dynamic>
        : <String, dynamic>{
            'domain': hostedDomain,
            'provider': 'email',
            'contact': 'gw-mcp-e2e-$run@example.test',
            'handle': 'gw-mcp-e2e-${run.substring(0, 16)}',
            'operationId': freshOperationId,
            'status': 'before_registration',
          };
    if (state['domain'] != hostedDomain ||
        state['provider'] != 'email' ||
        !RegExp(
          r'^gw-mcp-e2e-[a-f0-9]{32}@example\.test$',
        ).hasMatch(state['contact'] as String) ||
        !RegExp(
          r'^gw-mcp-e2e-[a-f0-9]{16}$',
        ).hasMatch(state['handle'] as String) ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(state['operationId'] as String) ||
        ![
          'before_registration',
          'registration_pending',
        ].contains(state['status'])) {
      throw StateError('hosted_fixture_resume_binding');
    }
    final operationId = state['operationId'] as String;
    void save() => intent.writeAsStringSync(jsonEncode(state), flush: true);
    save();
    protectE2ePathSync(intent.path);
    gateway = HostedGatewayFixture(state['contact'], state['handle'], '');
    phase = 'login';
    await gateway.login();
    phase = 'register';
    final result = await gateway.post('register', {
      'handle': state['handle'],
      'operation_id': operationId,
    });
    final taskId = result['task_id'];
    if (taskId is! String || taskId.isEmpty) {
      throw StateError('hosted_task_binding');
    }
    if (state['taskId'] != null && state['taskId'] != taskId) {
      throw StateError('hosted_fixture_resume_task_mismatch');
    }
    state['taskId'] = taskId;
    state['status'] = 'registration_pending';
    save();
    phase = 'task_poll';
    Map<String, dynamic>? completed;
    for (var attempt = 0; attempt < 60; attempt++) {
      final snapshot = await gateway.request('/connect/state');
      final tasks = (snapshot['tasks'] as List)
          .whereType<Map>()
          .where((task) => task['id'] == taskId)
          .toList();
      if (tasks.length != 1 || tasks.single['kind'] != 'register') {
        throw StateError('hosted_task_binding');
      }
      if (tasks.single['state'] == 'complete') {
        completed = snapshot;
        break;
      }
      if (['failed', 'cancelled'].contains(tasks.single['state'])) {
        throw StateError('hosted_registration_task_failed');
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (completed == null) throw StateError('hosted_registration_deadline');
    final identities = (completed['identities'] as List)
        .whereType<Map>()
        .where(
          (identity) =>
              identity['handle'] == '${state['handle']}.$hostedDomain',
        )
        .toList();
    if (identities.length != 1 ||
        !(identities.single['did'] as String).startsWith(
          'did:wba:$hostedDomain:',
        )) {
      throw StateError('hosted_identity_binding');
    }
    final email = File('${root.path}/email.private.json');
    email.writeAsStringSync(
      jsonEncode({...state, 'identity': identities.single}),
      flush: true,
    );
    protectE2ePathSync(email.path);
    final phone = File('${root.path}/phone.private.json');
    phone.writeAsStringSync(
      jsonEncode({
        'domain': hostedDomain, 'provider': 'phone',
        'contact':
            '+155500${random.nextInt(100000).toString().padLeft(5, '0')}',
        'handle': 'gw-mcp-e2e-${nonce(8)}',
        // The App requests a fresh operation-bound OTP immediately before use.
        'code': random.nextInt(1000000).toString().padLeft(6, '0'),
      }),
      flush: true,
    );
    protectE2ePathSync(phone.path);
    state['status'] = 'prepared_retained_isolated_fixture';
    save();
    stdout.writeln(
      jsonEncode({
        'status': 'prepared',
        'domain': hostedDomain,
        'emailFixturePath': email.path,
        'phoneFixturePath': phone.path,
        'cleanup': 'retained_isolated_gateway_device_recovery_material',
      }),
    );
  } catch (error) {
    final transport = error is http.ClientException
        ? [
            'HandshakeException',
            'Connection closed',
            'Connection reset',
            'Failed host lookup',
            'timed out',
            'CERTIFICATE_VERIFY_FAILED',
          ].where(error.message.contains).join(',')
        : '';
    final message =
        error is StateError &&
            RegExp(r'^hosted_[a-z0-9_]+$').hasMatch(error.message.toString())
        ? error.message
        : error.runtimeType.toString();
    stderr.writeln(
      'Hosted fixture preparation failed: $message phase=$phase transport=$transport; private intent retained.',
    );
    exitCode = 1;
  } finally {
    gateway?.close();
  }
}
