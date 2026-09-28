import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:awiki_me/src/data/avatar/avatar_image_cache_io.dart';

class Headers extends Fake implements HttpHeaders {
  final values = <String, String>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = '$value';
  }

  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  ContentType? get contentType => value('content-type') == null
      ? null
      : ContentType.parse(value('content-type')!);
}

class Response extends Stream<List<int>> implements HttpClientResponse {
  Response(
    this.body, {
    this.statusCode = 200,
    String cache = 'max-age=300',
    String mime = 'image/jpeg',
  }) {
    headers.set('content-type', mime);
    headers.set('cache-control', cache);
    headers.set('etag', '"version-1"');
  }
  final Uint8List body;
  @override
  final int statusCode;
  @override
  final headers = Headers();
  @override
  int get contentLength => body.length;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Future<Socket> detachSocket() async => SocketFake();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class SocketFake extends Fake implements Socket {
  @override
  void destroy() {}
}

class Request extends Fake implements HttpClientRequest {
  Request(this.response);
  final Future<HttpClientResponse> Function() response;
  @override
  final headers = Headers();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() => response();
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}
}

class Client extends Fake implements HttpClient {
  Client(this.respond);
  final Future<HttpClientResponse> Function(Uri) respond;
  final requests = <Request>[];
  final urls = <Uri>[];
  @override
  Future<HttpClientRequest> getUrl(Uri uri) async {
    urls.add(uri);
    final request = Request(() => respond(uri));
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late Uint8List jpeg;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('avatar-cache-test-');
    jpeg = img.encodeJpg(img.Image(width: 16, height: 16));
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  testWidgets(
    'deduplicates URI downloads across sizes, caches bytes and isolates owners',
    (tester) async {
      await tester.runAsync(() async {
        final response = Completer<HttpClientResponse>();
        final client = Client((_) => response.future);
        final cache = PlatformAvatarImageCache(
          'alice',
          client: client,
          directory: root,
        );
        final first = cache.load('https://example.com/a.jpg');
        final second = cache.load('https://example.com/a.jpg', edge: 512);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(client.requests.length, 1);
        expect(client.requests.single.headers.value('authorization'), isNull);
        expect(client.requests.single.headers.value('cookie'), isNull);
        response.complete(Response(jpeg));
        (await first)?.dispose();
        (await second)?.dispose();
        await cache.flush();
        cache.dispose();
        final offline = Client((_) async => throw StateError('offline'));
        final reopened = PlatformAvatarImageCache(
          'alice',
          client: offline,
          directory: root,
        );
        final warm = await reopened.load('https://example.com/a.jpg');
        expect(warm, isNotNull);
        warm?.dispose();
        await reopened.flush();
        reopened.dispose();
        expect(offline.requests, isEmpty);
        final other = PlatformAvatarImageCache(
          'bob',
          client: offline,
          directory: root,
        );
        expect(await other.load('https://example.com/a.jpg'), isNull);
        other.dispose();
      });
    },
  );

  testWidgets('revalidates expired ETag and honors no-store', (tester) async {
    await tester.runAsync(() async {
      final firstClient = Client(
        (_) async => Response(jpeg, cache: 'max-age=0'),
      );
      final first = PlatformAvatarImageCache(
        'alice',
        client: firstClient,
        directory: root,
      );
      (await first.load('https://example.com/a.jpg'))?.dispose();
      await first.flush();
      first.dispose();
      final revalidation = Client(
        (_) async => Response(Uint8List(0), statusCode: 304),
      );
      final second = PlatformAvatarImageCache(
        'alice',
        client: revalidation,
        directory: root,
      );
      final image = await second.load('https://example.com/a.jpg');
      expect(image, isNotNull);
      image?.dispose();
      expect(
        revalidation.requests.single.headers.value('if-none-match'),
        '"version-1"',
      );
      await second.flush();
      second.dispose();
      final noStore = PlatformAvatarImageCache(
        'alice',
        client: Client((_) async => Response(jpeg, cache: 'no-store')),
        directory: root,
      );
      (await noStore.load('https://example.com/private.jpg'))?.dispose();
      await noStore.flush();
      noStore.dispose();
      expect(
        (await root.list().toList())
            .where((entry) => entry.path.endsWith('.bin'))
            .length,
        1,
      );
    });
  });

  testWidgets(
    'bounds concurrency and rejects unsafe/malformed images with failure backoff',
    (tester) async {
      await tester.runAsync(() async {
        final pending = <Completer<HttpClientResponse>>[];
        final client = Client((_) {
          final response = Completer<HttpClientResponse>();
          pending.add(response);
          return response.future;
        });
        final cache = PlatformAvatarImageCache(
          'alice',
          client: client,
          directory: root,
        );
        final loads = List.generate(
          6,
          (index) => cache.load('https://example.com/$index.jpg'),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(client.requests.length, 4);
        for (final response in pending.toList()) {
          response.complete(Response(jpeg));
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        for (final response in pending.where((item) => !item.isCompleted)) {
          response.complete(Response(jpeg));
        }
        for (final image in await Future.wait(loads)) {
          image?.dispose();
        }
        await cache.flush();
        cache.dispose();
        final invalid = Client(
          (_) async => Response(
            Uint8List.fromList('<svg/>'.codeUnits),
            mime: 'image/svg+xml',
          ),
        );
        final guarded = PlatformAvatarImageCache(
          'alice',
          client: invalid,
          directory: root,
        );
        expect(await guarded.load('https://example.com/bad.jpg'), isNull);
        expect(await guarded.load('https://example.com/bad.jpg'), isNull);
        expect(
          await guarded.load('https://user:password@example.com/a.jpg'),
          isNull,
        );
        expect(invalid.requests.length, 1);
        guarded.dispose();
      });
    },
  );
  testWidgets(
    'deleting one owner clears its disk data and fences late downloads',
    (tester) async {
      await tester.runAsync(() async {
        final client = Client((_) async => Response(jpeg));
        final alice = PlatformAvatarImageCache(
          'clear-alice',
          client: client,
          directory: root,
        );
        final bob = PlatformAvatarImageCache(
          'clear-bob',
          client: client,
          directory: root,
        );
        (await alice.load('https://example.com/a.jpg'))?.dispose();
        (await bob.load('https://example.com/b.jpg'))?.dispose();
        await bob.flush();
        expect(await root.list().length, 4);
        final late = Completer<HttpClientResponse>();
        final pendingCache = PlatformAvatarImageCache(
          'clear-alice',
          client: Client((_) => late.future),
          directory: root,
        );
        final pending = pendingCache.load('https://example.com/late.jpg');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await clearAvatarImageCache('clear-alice', directory: root);
        late.complete(Response(jpeg));
        expect(await pending, isNull);
        await pendingCache.flush();
        expect(await root.list().length, 2);
        expect(await alice.load('https://example.com/a.jpg'), isNull);
        (await bob.load('https://example.com/b.jpg'))?.dispose();
        alice.dispose();
        bob.dispose();
        pendingCache.dispose();
      });
    },
  );
}
