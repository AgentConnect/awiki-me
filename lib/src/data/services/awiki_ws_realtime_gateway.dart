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
    Duration connectTimeout = const Duration(seconds: 3),
  }) : _messageServiceUrl =
           messageServiceUrl ??
           const String.fromEnvironment(
             'AWIKI_MESSAGE_SERVICE_URL',
             defaultValue: 'https://awiki.ai',
           ),
       _reconnectBaseDelay = reconnectBaseDelay,
       _reconnectMaxDelay = reconnectMaxDelay,
       _connectTimeout = connectTimeout;

  final String _messageServiceUrl;
  final Duration _reconnectBaseDelay;
  final Duration _reconnectMaxDelay;
  final Duration _connectTimeout;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  final StreamController<RealtimeConnectionStatus> _statusController =
      StreamController<RealtimeConnectionStatus>.broadcast();
  SessionIdentity? _session;
  RealtimeMessageHandler? _onMessage;
  bool _shouldRun = false;
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.idle;
  Duration _currentDelay = const Duration(seconds: 1);
  int _handshakeFailureCount = 0;

  @override
  bool get isConnected => _channel != null;

  @override
  RealtimeConnectionStatus get connectionStatus => _status;

  @override
  Stream<RealtimeConnectionStatus> get connectionStatusStream =>
      _statusController.stream;

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
    _setStatus(RealtimeConnectionStatus.connecting);
    await _openSocket();
  }

  @override
  Future<void> disconnect() async {
    _shouldRun = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _closeChannel(_channel);
    _channel = null;
    _setStatus(RealtimeConnectionStatus.idle);
  }

  Future<void> _openSocket() async {
    final session = _session;
    final onMessage = _onMessage;
    if (!_shouldRun || session == null || onMessage == null) {
      return;
    }
    final token = session.jwtToken ?? '';
    if (token.isEmpty) {
      _setStatus(RealtimeConnectionStatus.failed);
      throw StateError('Realtime connect requires jwt token.');
    }

    WebSocketChannel? channel;
    try {
      final uri = _buildWsUri();
      channel = connectAwikiWebSocket(
        uri,
        headers: <String, String>{'Authorization': 'Bearer $token'},
      );
      await channel.ready.timeout(_connectTimeout);
    } catch (error) {
      await _closeChannel(channel);
      if (_isAuthFailure(error)) {
        _shouldRun = false;
        _setStatus(RealtimeConnectionStatus.failed);
        return;
      }
      _scheduleReconnect(afterHandshakeFailure: true);
      return;
    }

    if (!_shouldRun) {
      await _closeChannel(channel);
      return;
    }

    _channel = channel;
    _currentDelay = _reconnectBaseDelay;
    _handshakeFailureCount = 0;
    _setStatus(RealtimeConnectionStatus.connected);
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
        method != 'group.state_changed' &&
        method != 'new_message' &&
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

  void _scheduleReconnect({bool afterHandshakeFailure = false}) {
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    if (!_shouldRun) {
      return;
    }
    if (afterHandshakeFailure) {
      _handshakeFailureCount += 1;
      if (_handshakeFailureCount >= 3) {
        _shouldRun = false;
        _setStatus(RealtimeConnectionStatus.disconnected);
        return;
      }
    }
    _setStatus(RealtimeConnectionStatus.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_currentDelay, () async {
      try {
        await _openSocket();
      } catch (_) {
        _scheduleReconnect(afterHandshakeFailure: true);
      }
    });
    final nextSeconds = (_currentDelay.inSeconds * 2).clamp(
      _reconnectBaseDelay.inSeconds,
      _reconnectMaxDelay.inSeconds,
    );
    _currentDelay = Duration(seconds: nextSeconds);
  }

  bool _isAuthFailure(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('401') ||
        raw.contains('unauthorized') ||
        raw.contains('invalidtoken') ||
        raw.contains('invalid token') ||
        raw.contains('session_unauthorized');
  }

  void _setStatus(RealtimeConnectionStatus status) {
    if (_status == status) {
      return;
    }
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  Future<void> _closeChannel(WebSocketChannel? channel) async {
    if (channel == null) {
      return;
    }
    try {
      await channel.sink.close().timeout(const Duration(seconds: 1));
    } catch (_) {
      // Closing can hang or fail when the remote peer already disappeared.
    }
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
