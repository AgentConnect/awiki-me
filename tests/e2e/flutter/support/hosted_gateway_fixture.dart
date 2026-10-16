// Fixed-instance synthetic OTP/browser fixture, never a production adapter.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const hostedDomain = 'mcp-adapt.anpclaw.com';
const hostedOrigin = 'https://$hostedDomain';

class HostedGatewayFixture {
  HostedGatewayFixture(
    this.contact,
    this.handle,
    this.did, {
    http.Client? client,
    this.provider = 'email',
  }) : _client = client ?? http.Client();
  final String provider;
  final String contact;
  final String handle;
  final String did;
  String _cookie = '';
  final http.Client _client;

  String managementOperationId(String session) {
    final bytes = sha256
        .convert(utf8.encode('hosted-app-management:$did:$session'))
        .bytes
        .take(16)
        .toList();
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String operationId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<HostedGatewayFixture> load(String path) async {
    final file = File(path);
    final stat = await file.stat();
    if (await FileSystemEntity.isLink(path) || stat.mode & 0x3f != 0) {
      throw StateError('hosted_fixture_permissions');
    }
    final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (value['domain'] != hostedDomain ||
        value['provider'] != 'email' ||
        !RegExp(
          r'^gw-mcp-e2e-[a-f0-9]{32}@example\.test$',
        ).hasMatch(value['contact'] as String)) {
      throw StateError('hosted_fixture_target');
    }
    final identity = value['identity'] as Map<String, dynamic>;
    if (identity['handle'] != '${value['handle']}.$hostedDomain' ||
        !(identity['did'] as String).startsWith('did:wba:$hostedDomain:')) {
      throw StateError('hosted_fixture_identity');
    }
    return HostedGatewayFixture(
      value['contact'] as String,
      value['handle'] as String,
      identity['did'] as String,
    );
  }

  static Future<({HostedGatewayFixture gateway, String code})>
  loadPhoneRegistration(String path) async {
    final file = File(path);
    final stat = await file.stat();
    if (await FileSystemEntity.isLink(path) || stat.mode & 0x3f != 0) {
      throw StateError('hosted_fixture_permissions');
    }
    final value = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (value['domain'] != hostedDomain ||
        value['provider'] != 'phone' ||
        !RegExp(r'^\+155500[0-9]{5}$').hasMatch(value['contact'] as String) ||
        !RegExp(
          r'^gw-mcp-e2e-[a-f0-9]{16}$',
        ).hasMatch(value['handle'] as String) ||
        !RegExp(r'^[0-9]{6}$').hasMatch(value['code'] as String)) {
      throw StateError('hosted_registration_fixture');
    }
    return (
      gateway: HostedGatewayFixture(
        value['contact'] as String,
        value['handle'] as String,
        '',
        provider: 'phone',
      ),
      code: value['code'] as String,
    );
  }

  Future<Map<String, dynamic>> waitForPairingResponse(String session) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      try {
        return await post('pair-device', {
          'handle': '$handle.$hostedDomain',
          'join_session_id': session,
          'refresh': true,
        });
      } on StateError catch (error) {
        if (error.message != 'hosted_pairing_response_pending') rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    throw StateError('hosted_pairing_response_deadline');
  }

  Future<void> waitForJoinRequest(String session) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      final value = await post('device-requests', {
        'handle': '$handle.$hostedDomain',
      });
      final requests = value['requests'];
      if (requests is! List) throw StateError('hosted_response_invalid');
      if (requests.any(
        (value) => value is Map && value['join_session_id'] == session,
      )) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError('hosted_request_delivery_deadline');
  }

  void close() => _client.close();

  Future<String> otp(String purpose, String target) async {
    final code = Random.secure().nextInt(1000000).toString().padLeft(6, '0');
    final process = await Process.start('ssh', const [
      'singapore-dev',
      'sudo',
      '-n',
      '/opt/awiki/mcp-adapt-20261015/services/user-service/current/.venv/bin/python',
      '/home/ecs-user/workspace-mcp-adapt-20261015/awiki-gateway/tests/e2e/hosted_seed_otp.py',
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final discarded = process.stderr.drain<void>();
    process.stdin.write(
      jsonEncode({
        'provider': provider,
        'contact': contact,
        'code': code,
        'purpose': purpose,
        'target': target,
      }),
    );
    await process.stdin.close();
    final exit = await process.exitCode.timeout(
      // Importing the exact User release can exceed 30s while the isolated
      // server builds. This bounds fixture setup, not the OTP validity period.
      const Duration(seconds: 120),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        throw StateError('hosted_fixture_timeout');
      },
    );
    final result = await output;
    await discarded;
    if (exit != 0 || result.trim() != '{"seeded":true}') {
      throw StateError('hosted_fixture_failed');
    }
    return code;
  }

  Future<Map<String, dynamic>> request(
    String path, [
    Map<String, dynamic>? body,
    int expectedStatus = 200,
  ]) async {
    if (!RegExp(r'^/connect(?:/[a-z-]+)?$').hasMatch(path)) {
      throw StateError('hosted_path_invalid');
    }
    final headers = {
      'Origin': hostedOrigin,
      'Accept': 'application/json',
      if (_cookie.isNotEmpty) 'Cookie': 'awiki_browser=$_cookie',
      if (body != null) 'Content-Type': 'application/json',
    };
    final request =
        http.Request(
            body == null ? 'GET' : 'POST',
            Uri.parse('$hostedOrigin$path'),
          )
          ..followRedirects = false
          ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 40));
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 40),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw StateError('hosted_response_limit');
      }
    }
    if (response.statusCode != expectedStatus) {
      if (path == '/connect/pair-device' &&
          body?['refresh'] == true &&
          response.statusCode == 409) {
        final value = jsonDecode(utf8.decode(bytes));
        if (value is Map &&
            value['error'] == 'device_join_notice_missing' &&
            value['retryable'] == true) {
          throw StateError('hosted_pairing_response_pending');
        }
      }
      throw StateError('hosted_http_status_${response.statusCode}');
    }
    final cookie = response.headers['set-cookie'];
    if (cookie != null) {
      final parsed = Cookie.fromSetCookieValue(cookie);
      if (parsed.name != 'awiki_browser' ||
          !parsed.secure ||
          !parsed.httpOnly ||
          !cookie.toLowerCase().contains('samesite=lax')) {
        throw StateError('hosted_cookie_flags');
      }
      _cookie = parsed.value;
    }
    if (path == '/connect') return {};
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(
    String action,
    Map<String, dynamic> body, {
    int expectedStatus = 200,
  }) async {
    final state = await request('/connect/state');
    return request('/connect/$action', {
      ...body,
      'csrf': state['csrf'],
    }, expectedStatus);
  }

  Future<void> login() async {
    await request('/connect');
    final code = await otp(
      'gateway',
      sha256.convert(utf8.encode(_cookie)).toString(),
    );
    await post('verify', {
      'provider': provider,
      'contact': contact,
      'code': code,
    });
    if ((await request('/connect/state'))['logged_in'] != true) {
      throw StateError('hosted_login_failed');
    }
  }
}
