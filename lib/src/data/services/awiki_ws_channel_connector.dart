import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectAwikiWebSocket(
  Uri uri, {
  Map<String, String>? headers,
}) {
  if (headers != null && headers.isNotEmpty) {
    throw UnsupportedError(
      'Bearer-authenticated WebSocket upgrade is not supported on Flutter Web.',
    );
  }
  return WebSocketChannel.connect(uri);
}
