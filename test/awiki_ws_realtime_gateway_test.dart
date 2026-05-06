import 'package:awiki_me/src/data/services/awiki_ws_realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds configured websocket URL with /im/ws path', () {
    final gateway = AwikiWsRealtimeGateway(wsBaseUrl: 'wss://awiki.ai');

    final uri = gateway.buildUriForTest('token');

    expect(uri.toString(), 'wss://awiki.ai/im/ws?token=token');
  });

  test('preserves configured /im/ws URL and appends token', () {
    final gateway = AwikiWsRealtimeGateway(
      wsBaseUrl: 'wss://awiki.ai/im/ws?client=mobile',
    );

    final uri = gateway.buildUriForTest('token');

    expect(uri.scheme, 'wss');
    expect(uri.path, '/im/ws');
    expect(uri.queryParameters['client'], 'mobile');
    expect(uri.queryParameters['token'], 'token');
  });
}
