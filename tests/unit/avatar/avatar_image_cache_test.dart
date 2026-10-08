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
    'agent byte downloads share the four-slot bound and deduplicate GIFs',
    (tester) async {
      await tester.runAsync(() async {
        final gif = File(
          'tests/unit/avatar/fixtures/agent.gif',
        ).readAsBytesSync();
        final gates = <Completer<void>>[];
        var active = 0;
        var peak = 0;
        final client = Client((_) async {
          final gate = Completer<void>();
          gates.add(gate);
          active++;
          if (active > peak) peak = active;
          await gate.future;
          active--;
          return Response(gif, mime: 'image/gif');
        });
        final cache = PlatformAvatarImageCache(
          'animated',
          directory: root,
          client: client,
        );
        final requests = [
          for (var i = 0; i < 6; i++)
            cache.loadBytes('https://example.com/$i.gif'),
        ];
        final duplicate = cache.loadBytes('https://example.com/0.gif');
        while (gates.length < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(gates, hasLength(4));
        expect(client.urls, hasLength(4));
        for (final gate in List<Completer<void>>.from(gates)) {
          gate.complete();
        }
        while (gates.length < 6) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        for (final gate in gates.skip(4)) {
          gate.complete();
        }
        final values = await Future.wait([...requests, duplicate]);
        expect(values, everyElement(isNotNull));
        expect(values.first, gif);
        expect(peak, 4);
        expect(client.urls, hasLength(6));
        expect(await cache.loadBytes('https://example.com/0.gif'), gif);
        expect(client.urls, hasLength(6));
        expect(
          client.requests.every(
            (request) => request.headers.value('authorization') == null,
          ),
          isTrue,
        );
        cache.dispose();
        expect(await cache.loadBytes('https://example.com/0.gif'), isNull);
      });
    },
  );

  testWidgets(
    'full disk cache evicts oldest bytes including metadata before new writes',
    (tester) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 4; i++) {
          final file = File('${root.path}/old-$i.bin');
          final handle = await file.open(mode: FileMode.write);
          await handle.truncate(16 * 1024 * 1024);
          await handle.close();
          await file.setLastModified(DateTime.utc(2020, 1, i + 1));
          await File('${root.path}/old-$i.json').writeAsString('{}');
        }
        final cache = PlatformAvatarImageCache(
          'bounded',
          directory: root,
          client: Client((_) async => Response(jpeg)),
        );
        final image = await cache.load('https://example.com/new.jpg');
        expect(image, isNotNull);
        image?.dispose();
        await cache.flush();
        cache.dispose();
        var size = 0;
        await for (final file in root.list()) {
          if (file is File) size += await file.length();
        }
        expect(size, lessThanOrEqualTo(64 * 1024 * 1024));
        expect(await File('${root.path}/old-0.bin').exists(), isFalse);
        expect(await File('${root.path}/old-0.json').exists(), isFalse);
      });
    },
  );

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
        final metadata = (await root.list().toList())
            .whereType<File>()
            .singleWhere((file) => file.path.endsWith('.json'));
        final savedAt = DateTime.utc(2026, 1, 1);
        await metadata.setLastModified(savedAt);
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
        expect(
          (await metadata.stat()).modified.toUtc(),
          savedAt,
          reason: 'A fresh disk hit must not rewrite the cached entry',
        );
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
  testWidgets(
    'animated cache persists, revalidates 304, updates stable URI and works offline',
    (tester) async {
      await tester.runAsync(() async {
        final gif = File(
          'tests/unit/avatar/fixtures/agent.gif',
        ).readAsBytesSync();
        const uri = 'https://other.example/avatars/presets/custom.gif';
        var count = 0;
        final client = Client((_) async {
          count++;
          if (count == 2) {
            return Response(Uint8List(0), statusCode: 304, cache: 'max-age=0');
          }
          return Response(
            count == 3 ? jpeg : gif,
            mime: count == 3 ? 'image/jpeg' : 'image/gif',
            cache: 'max-age=0',
          );
        });
        final cache = PlatformAvatarImageCache(
          'alice',
          client: client,
          directory: root,
        );
        final first = await cache.loadBytes(uri);
        expect(first, gif);
        final second = await cache.loadBytes(uri, force: true);
        expect(
          identical(first, second),
          isTrue,
          reason: '304 retains the same byte/image identity',
        );
        expect(
          client.requests[1].headers.value('if-none-match'),
          '"version-1"',
        );
        expect(await cache.loadBytes(uri, force: true), jpeg);
        await cache.flush();
        cache.dispose();
        final offline = Client((_) async => throw StateError('offline'));
        final reopened = PlatformAvatarImageCache(
          'alice',
          client: offline,
          directory: root,
        );
        expect(await reopened.loadBytes(uri), jpeg);
        reopened.dispose();
        final other = PlatformAvatarImageCache(
          'bob',
          client: offline,
          directory: root,
        );
        expect(await other.loadBytes(uri), isNull);
        other.dispose();
      });
    },
  );
  testWidgets('a new response without ETag clears the previous validator', (
    tester,
  ) async {
    await tester.runAsync(() async {
      var count = 0;
      final client = Client((_) async {
        final response = Response(jpeg, cache: 'max-age=0');
        if (count++ > 0) (response.headers as Headers).values.remove('etag');
        return response;
      });
      final cache = PlatformAvatarImageCache(
        'etag-reset',
        client: client,
        directory: root,
      );
      for (var i = 0; i < 3; i++) {
        expect(
          await cache.loadBytes('https://example.com/change.jpg', force: true),
          isNotNull,
        );
      }
      expect(client.requests[1].headers.value('if-none-match'), '"version-1"');
      expect(client.requests[2].headers.value('if-none-match'), isNull);
      cache.dispose();
    });
  });

  testWidgets('decoded-cache budget includes retained encoded bytes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final padded = Uint8List(3 * 1024 * 1024)..setAll(0, jpeg);
      final cache = PlatformAvatarImageCache(
        'retained-bytes',
        client: Client((_) async => Response(padded)),
        directory: root,
      );
      final first = await cache.load('https://example.com/0.jpg');
      expect(first, isNotNull);
      for (var i = 1; i < 6; i++) {
        (await cache.load('https://example.com/$i.jpg'))?.dispose();
      }
      final again = await cache.load('https://example.com/0.jpg');
      expect(again, isNotNull);
      expect(
        again!.isCloneOf(first!),
        isFalse,
        reason:
            'The old decode must be evicted once retained bytes exceed 16 MiB',
      );
      first.dispose();
      again.dispose();
      cache.dispose();
    });
  });
}
