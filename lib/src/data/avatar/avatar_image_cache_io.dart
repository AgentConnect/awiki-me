import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'avatar_image_cache.dart';

class _DecodedAvatar {
  _DecodedAvatar(this.image, this.until);
  final ui.Image image;
  final DateTime until;
  int get bytes => image.width * image.height * 4;
}

/// Public-only, owner-fenced byte/decoded caches. No SDK credential client.
class PlatformAvatarImageCache implements AvatarImageCache {
  PlatformAvatarImageCache(
    String owner, {
    HttpClient? client,
    Directory? directory,
  }) : _owner = sha256.convert(utf8.encode(owner)).toString(),
       _http =
           client ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 8)),
       _root = directory == null ? null : Future.value(directory);
  static const _diskLimit = 64 * 1024 * 1024;
  static const _memoryLimit = 16 * 1024 * 1024;
  static const _downloadLimit = 1024 * 1024;
  final String _owner;
  final HttpClient _http;
  final _memory = <String, _DecodedAvatar>{};
  final _pending = <String, Future<ui.Image?>>{};
  final _bytePending = <String, Future<(Uint8List, DateTime, String?, bool)>>{};
  final _retryAfter = <String, DateTime>{};
  final _slots = Queue<Completer<void>>();
  int _running = 0;
  bool _disposed = false;
  Future<Directory>? _root;
  Future<void> _diskWrites = Future.value();

  Future<void> flush() => _diskWrites;

  Future<Directory> _directory() => _root ??= () async {
    final root = Directory(
      '${(await getApplicationCacheDirectory()).path}/public-avatars-v1',
    );
    return root.create(recursive: true);
  }();

  @override
  Future<ui.Image?> load(String raw, {int edge = 128}) async {
    final uri = safeAvatarUri(raw);
    if (_disposed || uri == null) return null;
    edge = edge <= 128 ? 128 : 512;
    final key = '$uri@$edge';
    final cached = _memory.remove(key);
    if (cached != null) {
      if (cached.until.isAfter(DateTime.now())) {
        _memory[key] = cached;
        return cached.image.clone();
      }
      cached.image.dispose();
    }
    if (_retryAfter[key]?.isAfter(DateTime.now()) == true) return null;
    // Callers receive independent handles to one shared decoded allocation.
    final result = await (_pending[key] ??= _load(
      uri,
      edge,
      key,
    ).whenComplete(() { _pending.remove(key); }));
    return _disposed ? null : result?.clone();
  }

  Future<ui.Image?> _load(Uri uri, int edge, String key) async {
    if (_running >= 4) {
      final slot = Completer<void>();
      _slots.add(slot);
      await slot.future;
    } else {
      _running++;
    }
    try {
      if (_disposed) return null;
      final root = await _directory();
      final name = sha256.convert(utf8.encode('$_owner|$uri')).toString();
      final dataFile = File('${root.path}/$name.bin');
      final metaFile = File('${root.path}/$name.json');
      Uint8List? data;
      DateTime until = DateTime.now();
      String? etag;
      var canStore = true;
      try {
        final meta = jsonDecode(await metaFile.readAsString()) as Map;
        until = DateTime.fromMillisecondsSinceEpoch(meta['expires'] as int);
        etag = meta['etag'] as String?;
        if (await dataFile.length() <= _downloadLimit) {
          data = await dataFile.readAsBytes();
          await dataFile.setLastModified(DateTime.now());
        }
      } catch (_) {
        /* An interrupted cache write is a miss. */
      }
      if (data == null || !until.isAfter(DateTime.now())) {
        final byteKey = uri.toString();
        final response = await (_bytePending[byteKey] ??= _download(
          uri,
          previous: data,
          etag: etag,
        ).whenComplete(() { _bytePending.remove(byteKey); }));
        data = response.$1;
        until = response.$2;
        etag = response.$3;
        canStore = response.$4;
      }
      if (_disposed) return null;
      final buffer = await ui.ImmutableBuffer.fromUint8List(data);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      ui.Image image;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width > 4096 ||
            descriptor.height > 4096 ||
            descriptor.width * descriptor.height > 16000000) {
          throw const FormatException('avatar.decode_limit');
        }
        codec = await descriptor.instantiateCodec(
          targetWidth: descriptor.width >= descriptor.height ? edge : null,
          targetHeight: descriptor.height > descriptor.width ? edge : null,
        );
        if (codec.frameCount != 1) {
          throw const FormatException('avatar.animation');
        }
        image = (await codec.getNextFrame()).image;
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
      if (_disposed) {
        image.dispose();
        return null;
      }
      _memory[key] = _DecodedAvatar(image, until);
      while (_memory.values.fold<int>(0, (sum, item) => sum + item.bytes) >
          _memoryLimit) {
        _memory.remove(_memory.keys.first)?.image.dispose();
      }
      // Cache failures must never turn a successfully decoded avatar into an error.
      final bytes = data;
      _diskWrites = _diskWrites
          .then((_) async {
            if (_disposed) return;
            if (!canStore) {
              if (await dataFile.exists()) await dataFile.delete();
              if (await metaFile.exists()) await metaFile.delete();
              return;
            }
            final temporary = File('${dataFile.path}.part');
            await temporary.writeAsBytes(bytes, flush: true);
            await temporary.rename(dataFile.path);
            await metaFile.writeAsString(
              jsonEncode({
                'expires': until.millisecondsSinceEpoch,
                'etag': etag,
              }),
            );
            await _trim(root);
          })
          .catchError((Object _) {});
      return image;
    } catch (_) {
      _retryAfter[key] = DateTime.now().add(const Duration(seconds: 30));
      if (_retryAfter.length > 512) _retryAfter.remove(_retryAfter.keys.first);
      return null;
    } finally {
      if (_slots.isNotEmpty) {
        _slots.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }

  Future<(Uint8List, DateTime, String?, bool)> _download(
    Uri uri, {
    Uint8List? previous,
    String? etag,
  }) async {
    HttpClientRequest? active;
    var expired = false;
    final timeout = Timer(const Duration(seconds: 20), () {
      expired = true;
      active?.abort(const FormatException('avatar.timeout'));
    });
    try {
      for (var redirects = 0; redirects <= 3; redirects++) {
        if (_disposed || expired || safeAvatarUri(uri.toString()) == null) {
          throw const FormatException('avatar.uri');
        }
        final request = await _http.getUrl(uri);
        active = request;
        if (expired) {
          request.abort();
          throw const FormatException('avatar.timeout');
        }
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          'image/jpeg,image/png,image/webp',
        );
        if (previous != null && etag != null && etag.length <= 512) {
          request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
        }
        final response = await request.close();
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.detachSocket().then((socket) => socket.destroy());
          if (location == null) throw const FormatException('avatar.redirect');
          uri = uri.resolve(location);
          // Validators belong to the exact origin resource.
          etag = null;
          previous = null;
          continue;
        }
        final policy =
            response.headers
                .value(HttpHeaders.cacheControlHeader)
                ?.toLowerCase() ??
            '';
        final maxAge = int.tryParse(
          RegExp(r'(?:^|[,\s])max-age=(\d+)').firstMatch(policy)?.group(1) ??
              '',
        );
        final age = int.tryParse(response.headers.value('age') ?? '') ?? 0;
        final canStore = !policy.contains('no-store');
        final ttl = !canStore || policy.contains('no-cache')
            ? 0
            : ((maxAge ?? 300) - age).clamp(0, 604800);
        final until = DateTime.now().add(Duration(seconds: ttl));
        final nextEtag = response.headers.value(HttpHeaders.etagHeader) ?? etag;
        if (response.statusCode == 304 && previous != null) {
          await response.drain<void>();
          return (previous, until, nextEtag, canStore);
        }
        if (response.statusCode != 200 ||
            response.contentLength > _downloadLimit ||
            !{
              'image/jpeg',
              'image/png',
              'image/webp',
            }.contains(response.headers.contentType?.mimeType)) {
          await response.detachSocket().then((socket) => socket.destroy());
          throw const FormatException('avatar.response');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > _downloadLimit) {
            throw const FormatException('avatar.byte_limit');
          }
          bytes.add(chunk);
        }
        return (bytes.takeBytes(), until, nextEtag, canStore);
      }
      throw const FormatException('avatar.redirect_limit');
    } finally {
      timeout.cancel();
    }
  }

  Future<void> _trim(Directory root) async {
    final entries = <(File, FileStat)>[];
    var total = 0;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.bin')) {
        final stat = await entity.stat();
        total += stat.size;
        entries.add((entity, stat));
      }
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final entry in entries) {
      if (total <= _diskLimit) break;
      total -= entry.$2.size;
      await entry.$1.delete();
      final meta = File(entry.$1.path.replaceFirst(RegExp(r'\.bin$'), '.json'));
      if (await meta.exists()) await meta.delete();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _http.close(force: true);
    for (final entry in _memory.values) {
      entry.image.dispose();
    }
    _memory.clear();
    _retryAfter.clear();
  }
}
