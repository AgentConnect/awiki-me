import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/session_identity.dart';
import '../../domain/services/realtime_gateway.dart';
import 'awiki_ws_channel_connector.dart'
    if (dart.library.io) 'awiki_ws_channel_connector_io.dart';

class AwikiWsRealtimeGateway implements RealtimeGateway {
  AwikiWsRealtimeGateway({
    String? messageServiceUrl,
    Duration reconnectBaseDelay = const Duration(seconds: 1),
    Duration reconnectMaxDelay = const Duration(seconds: 30),
  }) : _messageServiceUrl =
           messageServiceUrl ??
           const String.fromEnvironment(
             'AWIKI_MESSAGE_SERVICE_URL',
             defaultValue: 'https://awiki.ai',
           ),
       _reconnectBaseDelay = reconnectBaseDelay,
       _reconnectMaxDelay = reconnectMaxDelay;

  final String _messageServiceUrl;
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

  Uri buildUriForTest() => _buildWsUri();

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

    final uri = _buildWsUri();
    final channel = connectAwikiWebSocket(
      uri,
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
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
    if (method != 'direct.incoming' &&
        method != 'group.incoming' &&
        method != 'group.state_changed') {
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

  Uri _buildWsUri() {
    final uri = Uri.parse(_messageServiceUrl.trim());
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final normalizedBasePath = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '$normalizedBasePath/im/ws',
    );
  }
}
