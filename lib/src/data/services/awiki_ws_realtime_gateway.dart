import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/session_identity.dart';
import '../../domain/services/realtime_gateway.dart';

class AwikiWsRealtimeGateway implements RealtimeGateway {
  AwikiWsRealtimeGateway({
    String? wsBaseUrl,
    Duration reconnectBaseDelay = const Duration(seconds: 1),
    Duration reconnectMaxDelay = const Duration(seconds: 30),
  }) : _wsBaseUrl =
           wsBaseUrl ??
           const String.fromEnvironment('AWIKI_WS_URL', defaultValue: ''),
       _reconnectBaseDelay = reconnectBaseDelay,
       _reconnectMaxDelay = reconnectMaxDelay;

  final String _wsBaseUrl;
  final Duration _reconnectBaseDelay;
  final Duration _reconnectMaxDelay;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  SessionIdentity? _session;
  RealtimeMessageHandler? _onMessage;
  bool _shouldRun = false;
  Duration _currentDelay = const Duration(seconds: 1);

  @override
  bool get isConnected => _channel != null;

  Uri buildUriForTest(String token) => _buildWsUri(token);

  @override
  Future<void> connect({
    required SessionIdentity session,
    required RealtimeMessageHandler onMessage,
  }) async {
    _session = session;
    _onMessage = onMessage;
    _shouldRun = true;
    _currentDelay = _reconnectBaseDelay;
    await _openSocket();
  }

  @override
  Future<void> disconnect() async {
    _shouldRun = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> _openSocket() async {
    final session = _session;
    final onMessage = _onMessage;
    if (!_shouldRun || session == null || onMessage == null) {
      return;
    }
    final token = session.jwtToken ?? '';
    if (token.isEmpty) {
      throw StateError('Realtime connect requires jwt token.');
    }

    final uri = _buildWsUri(token);
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    _subscription = channel.stream.listen(
      (event) async {
        await _handleSocketEvent(event, onMessage: onMessage);
      },
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
      cancelOnError: true,
    );
  }

  Future<void> _handleSocketEvent(
    dynamic event, {
    required RealtimeMessageHandler onMessage,
  }) async {
    if (event is! String) {
      return;
    }
    final decoded = jsonDecode(event);
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    final method = decoded['method']?.toString() ?? '';
    if (method != 'new_message' &&
        method != 'direct.new_message' &&
        method != 'group.new_message' &&
        method != 'inbox.updated' &&
        method != 'message.new') {
      return;
    }
    final params = decoded['params'];
    if (params is! Map<String, dynamic>) {
      return;
    }
    final normalized = params.map<String, Object?>(
      (key, value) => MapEntry(key, value),
    );
    await onMessage(normalized);
  }

  void _scheduleReconnect() {
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    if (!_shouldRun) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_currentDelay, () async {
      await _openSocket();
    });
    final nextSeconds = (_currentDelay.inSeconds * 2).clamp(
      _reconnectBaseDelay.inSeconds,
      _reconnectMaxDelay.inSeconds,
    );
    _currentDelay = Duration(seconds: nextSeconds);
  }

  Uri _buildWsUri(String token) {
    final configured = _wsBaseUrl.trim();
    if (configured.isNotEmpty) {
      final base = configured.endsWith('/')
          ? configured.substring(0, configured.length - 1)
          : configured;
      final uri = Uri.parse(base);
      if (uri.path.endsWith('/im/ws')) {
        return uri.replace(
          queryParameters: <String, String>{
            ...uri.queryParameters,
            'token': token,
          },
        );
      }
      return Uri.parse('$base/im/ws?token=$token');
    }
    const messageService = String.fromEnvironment(
      'AWIKI_MESSAGE_SERVICE_URL',
      defaultValue: 'https://awiki.ai',
    );
    final uri = Uri.parse(messageService);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/im/ws',
      queryParameters: <String, String>{'token': token},
    );
  }
}
