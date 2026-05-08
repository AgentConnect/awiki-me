import 'dart:async';
import 'dart:io';

import 'package:awiki_me/src/data/services/awiki_ws_realtime_gateway.dart';
import 'package:awiki_me/src/domain/entities/session_identity.dart';
import 'package:awiki_me/src/domain/services/realtime_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds configured websocket URL with /im/ws path', () {
    final gateway = AwikiWsRealtimeGateway(
      messageServiceUrl: 'https://awiki.ai',
    );

    final uri = gateway.buildUriForTest();

    expect(uri.toString(), 'wss://awiki.ai/im/ws');
  });

  test('derives /im/ws from configured service base URL', () {
    final gateway = AwikiWsRealtimeGateway(
      messageServiceUrl: 'http://127.0.0.1:18080',
    );

    final uri = gateway.buildUriForTest();

    expect(uri.toString(), 'ws://127.0.0.1:18080/im/ws');
  });

  test('preserves service base path when deriving /im/ws', () {
    final gateway = AwikiWsRealtimeGateway(
      messageServiceUrl: 'https://example.com/service-base/',
    );

    final uri = gateway.buildUriForTest();

    expect(uri.toString(), 'wss://example.com/service-base/im/ws');
  });

  test('opens websocket with bearer authorization header', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final captured = Completer<HttpRequest>();
    final done = Completer<void>();
    unawaited(
      server.listen((request) async {
        captured.complete(request);
        final socket = await WebSocketTransformer.upgrade(request);
        await socket.close();
        done.complete();
      }).asFuture<void>(),
    );
    final gateway = AwikiWsRealtimeGateway(
      messageServiceUrl: 'http://127.0.0.1:${server.port}',
    );

    await gateway.connect(
      session: const SessionIdentity(
        did: 'did:wba:awiki.ai:agents:alice:e1_alice',
        credentialName: 'default',
        displayName: 'Alice',
        jwtToken: 'jwt-token',
      ),
      onMessage: (_) async {},
    );

    final request = await captured.future.timeout(const Duration(seconds: 2));
    expect(request.uri.path, '/im/ws');
    expect(request.uri.queryParameters.containsKey('token'), isFalse);
    expect(
      request.headers.value(HttpHeaders.authorizationHeader),
      'Bearer jwt-token',
    );

    await done.future.timeout(const Duration(seconds: 2));
    await gateway.disconnect();
    await server.close(force: true);
  });

  test('reconnects automatically after socket closes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <HttpRequest>[];
    final secondConnection = Completer<void>();
    unawaited(
      server.listen((request) async {
        requests.add(request);
        final socket = await WebSocketTransformer.upgrade(request);
        if (requests.length == 1) {
          await socket.close();
          return;
        }
        secondConnection.complete();
      }).asFuture<void>(),
    );
    final gateway = AwikiWsRealtimeGateway(
      messageServiceUrl: 'http://127.0.0.1:${server.port}',
      reconnectBaseDelay: const Duration(milliseconds: 10),
      reconnectMaxDelay: const Duration(milliseconds: 20),
    );
    final statuses = <RealtimeConnectionStatus>[];
    final reconnected = Completer<void>();
    final statusSubscription = gateway.connectionStatusStream.listen((status) {
      statuses.add(status);
      if (statuses.contains(RealtimeConnectionStatus.reconnecting) &&
          status == RealtimeConnectionStatus.connected &&
          !reconnected.isCompleted) {
        reconnected.complete();
      }
    });

    await gateway.connect(
      session: const SessionIdentity(
        did: 'did:wba:awiki.ai:agents:alice:e1_alice',
        credentialName: 'default',
        displayName: 'Alice',
        jwtToken: 'jwt-token',
      ),
      onMessage: (_) async {},
    );

    await secondConnection.future.timeout(const Duration(seconds: 2));
    await reconnected.future.timeout(const Duration(seconds: 2));

    expect(requests, hasLength(2));
    expect(statuses, contains(RealtimeConnectionStatus.reconnecting));
    expect(gateway.connectionStatus, RealtimeConnectionStatus.connected);

    await statusSubscription.cancel();
    await gateway.disconnect();
    await server.close(force: true);
  });

  test('keeps retrying when the initial websocket upgrade fails', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestCount = 0;
    final secondConnection = Completer<void>();
    unawaited(
      server.listen((request) async {
        requestCount += 1;
        if (requestCount == 1) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        unawaited(socket.done);
        secondConnection.complete();
      }).asFuture<void>(),
    );
    final gateway = AwikiWsRealtimeGateway(
      messageServiceUrl: 'http://127.0.0.1:${server.port}',
      reconnectBaseDelay: const Duration(milliseconds: 10),
      reconnectMaxDelay: const Duration(milliseconds: 20),
    );
    final connected = Completer<void>();
    final statusSubscription = gateway.connectionStatusStream.listen((status) {
      if (requestCount >= 2 &&
          status == RealtimeConnectionStatus.connected &&
          !connected.isCompleted) {
        connected.complete();
      }
    });

    await gateway.connect(
      session: const SessionIdentity(
        did: 'did:wba:awiki.ai:agents:alice:e1_alice',
        credentialName: 'default',
        displayName: 'Alice',
        jwtToken: 'jwt-token',
      ),
      onMessage: (_) async {},
    );

    await secondConnection.future.timeout(const Duration(seconds: 2));
    await connected.future.timeout(const Duration(seconds: 2));

    expect(requestCount, 2);
    expect(gateway.connectionStatus, RealtimeConnectionStatus.connected);

    await statusSubscription.cancel();
    await gateway.disconnect();
    await server.close(force: true);
  });
}
