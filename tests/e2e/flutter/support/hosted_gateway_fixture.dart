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
  }) : _client = client ?? http.Client();
  final String contact;
  final String handle;
  final String did;
  String _cookie = '';
  final http.Client _client;

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
        'provider': 'email',
        'contact': contact,
        'code': code,
        'purpose': purpose,
        'target': target,
      }),
    );
    await process.stdin.close();
    final exit = await process.exitCode.timeout(
      const Duration(seconds: 30),
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
    if (response.statusCode != 200) {
      throw StateError('hosted_http_failed');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 40),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw StateError('hosted_response_limit');
      }
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
    Map<String, dynamic> body,
  ) async {
    final state = await request('/connect/state');
    return request('/connect/$action', {...body, 'csrf': state['csrf']});
  }

  Future<void> login() async {
    await request('/connect');
    final code = await otp(
      'gateway',
      sha256.convert(utf8.encode(_cookie)).toString(),
    );
    await post('verify', {
      'provider': 'email',
      'contact': contact,
      'code': code,
    });
    if ((await request('/connect/state'))['logged_in'] != true) {
      throw StateError('hosted_login_failed');
    }
  }
}
