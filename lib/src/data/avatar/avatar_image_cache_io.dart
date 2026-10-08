import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'avatar_image_cache.dart';

final _ownerEpochs = <String, int>{};
Future<void> _diskOperations = Future.value();
final _diskWriteWindows = <String, (int, int)>{};

Future<Directory> _avatarDirectory() async => Directory(
  "${(await getApplicationCacheDirectory()).path}/public-avatars-v1",
).create(recursive: true);

Future<void> clearAvatarImageCache(String owner, {Directory? directory}) async {
  final key = sha256.convert(utf8.encode(owner)).toString();
  _ownerEpochs[key] = (_ownerEpochs[key] ?? 0) + 1;
  final operation = _diskOperations.then((_) async {
    final root = directory ?? await _avatarDirectory();
    if (!await root.exists()) return;
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File && entity.uri.pathSegments.last.startsWith("$key-")) {
        await entity.delete();
      }
    }
  });
  _diskOperations = operation.catchError((Object _) {});
  await operation;
}

class _DecodedAvatar {
  _DecodedAvatar(this.image, this.until);
  final ui.Image image;
  final DateTime until;
  int get bytes => image.width * image.height * 4;
}

/// Public-only, owner-fenced byte/decoded caches. No SDK credential client.
class PlatformAvatarImageCache implements AvatarImageCache, AvatarByteCache {
  PlatformAvatarImageCache(
    String owner, {
    HttpClient? client,
    Directory? directory,
  }) : _owner = sha256.convert(utf8.encode(owner)).toString(),
       _http =
           client ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 8)),
       _root = directory == null ? null : Future.value(directory) {
    _epoch = _ownerEpochs[_owner] ?? 0;
  }
  static const _diskLimit = 64 * 1024 * 1024;
  static const _memoryLimit = 16 * 1024 * 1024;
  static const _downloadLimit = 1024 * 1024;
  final _animationBytes = <String, (Uint8List, DateTime)>{};
  final _animationPending = <String, Future<Uint8List?>>{};

  @override
  Future<Uint8List?> loadBytes(String raw) async {
    final uri = safeAvatarUri(raw);
    if (uri == null || _inactive) return null;
    final cached = _animationBytes[raw];
    if (cached != null && DateTime.now().isBefore(cached.$2)) return cached.$1;
    _animationBytes.remove(raw);
    return _animationPending[raw] ??= _loadAnimation(uri, raw).whenComplete(() {
      _animationPending.remove(raw);
    });
  }

  Future<Uint8List?> _loadAnimation(Uri uri, String raw) async {
    if (_running >= 4) {
      final wait = Completer<void>();
      _slots.add(wait);
      await wait.future;
    } else {
      _running++;
    }
    try {
      if (_inactive) return null;
      final result = await _download(
        uri,
        byteLimit: 5 * 1024 * 1024,
        allowGif: true,
      );
      if (_inactive) return null;
      final buffer = await ui.ImmutableBuffer.fromUint8List(result.$1);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width > 4096 ||
            descriptor.height > 4096 ||
            descriptor.width * descriptor.height > 16000000) {
          return null;
        }
        codec = await descriptor.instantiateCodec(
          targetWidth: 256,
          targetHeight: 256,
        );
        if (codec.frameCount > 120 ||
            descriptor.width * descriptor.height * codec.frameCount >
                24000000) {
          return null;
        }
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
      if (_inactive) return null;
      if (result.$4) {
        _animationBytes[raw] = (result.$1, result.$2);
        while (_animationBytes.values.fold<int>(
              0,
              (sum, bytes) => sum + bytes.$1.length,
            ) >
            16 * 1024 * 1024) {
          _animationBytes.remove(_animationBytes.keys.first);
        }
      }
      return result.$1;
    } catch (_) {
      return null;
    } finally {
      if (_slots.isNotEmpty) {
        _slots.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }

  final String _owner;
  final HttpClient _http;
  final _memory = <String, _DecodedAvatar>{};
  final _pending = <String, Future<ui.Image?>>{};
  final _bytePending = <String, Future<(Uint8List, DateTime, String?, bool)>>{};
  final _retryAfter = <String, DateTime>{};
  final _slots = Queue<Completer<void>>();
  int _running = 0;
  bool _disposed = false;
  late final int _epoch;
  bool get _inactive => _disposed || _epoch != (_ownerEpochs[_owner] ?? 0);
  Future<Directory>? _root;
  Future<void> _diskWrites = Future.value();
  // Reserve a small write window so maintenance is amortized without crossing
  // the hard disk/count limits. Disk hits never rewrite or rescan the cache.
  static const _writeWindow = 4 * 1024 * 1024;

  Future<void> flush() => _diskWrites;

  Future<Directory> _directory() => _root ??= _avatarDirectory();

  @override
  Future<ui.Image?> load(
    String raw, {
    int edge = 128,
    bool force = false,
  }) async {
    final uri = safeAvatarUri(raw);
    if (_inactive || uri == null) return null;
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
    if (!force && _retryAfter[key]?.isAfter(DateTime.now()) == true) {
      return null;
    }
    // Callers receive independent handles to one shared decoded allocation.
    final result = await (_pending[key] ??= _load(uri, edge, key).whenComplete(
      () {
        _pending.remove(key);
      },
    ));
    return _inactive ? null : result?.clone();
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
      if (_inactive) return null;
      final root = await _directory();
      final name = '$_owner-${sha256.convert(utf8.encode(uri.toString()))}';
      final dataFile = File('${root.path}/$name.bin');
      final metaFile = File('${root.path}/$name.json');
      Uint8List? data;
      DateTime until = DateTime.now();
      String? etag;
      var canStore = true;
      var downloaded = false;
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
        downloaded = true;
        final byteKey = uri.toString();
        final response = await (_bytePending[byteKey] ??=
            _download(uri, previous: data, etag: etag).whenComplete(() {
              _bytePending.remove(byteKey);
            }));
        data = response.$1;
        until = response.$2;
        etag = response.$3;
        canStore = response.$4;
      }
      if (_inactive) return null;
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
      if (_inactive) {
        image.dispose();
        return null;
      }
      _memory[key] = _DecodedAvatar(image, until);
      while (_memory.values.fold<int>(0, (sum, item) => sum + item.bytes) >
          _memoryLimit) {
        _memory.remove(_memory.keys.first)?.image.dispose();
      }
      // Cache failures must never turn a successfully decoded avatar into an error.
      if (!downloaded) return image;
      final bytes = data;
      _diskWrites = _diskOperations
          .then((_) async {
            if (_inactive) return;
            if (!canStore) {
              if (await dataFile.exists()) await dataFile.delete();
              if (await metaFile.exists()) await metaFile.delete();
              return;
            }
            final metadata = utf8.encode(
              jsonEncode({
                'expires': until.millisecondsSinceEpoch,
                'etag': etag,
              }),
            );
            final size = bytes.length + metadata.length;
            var window = _diskWriteWindows[root.path] ?? (_writeWindow, 64);
            if (window.$1 + size > _writeWindow || window.$2 >= 64) {
              await _trim(root);
              window = (0, 0);
            }
            final temporary = File('${dataFile.path}.part');
            await temporary.writeAsBytes(bytes, flush: true);
            await temporary.rename(dataFile.path);
            await metaFile.writeAsBytes(metadata);
            _diskWriteWindows[root.path] = (window.$1 + size, window.$2 + 1);
            if (_diskWriteWindows.length > 8) {
              _diskWriteWindows.remove(_diskWriteWindows.keys.first);
            }
          })
          .catchError((Object _) {});
      _diskOperations = _diskWrites;
      // Keep pending encoded buffers inside the same four-slot budget. A slow
      // disk must not turn fast downloads into an unbounded write queue.
      await _diskWrites;
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
    int byteLimit = _downloadLimit,
    bool allowGif = false,
  }) async {
    HttpClientRequest? active;
    var expired = false;
    final timeout = Timer(const Duration(seconds: 20), () {
      expired = true;
      active?.abort(const FormatException('avatar.timeout'));
    });
    try {
      for (var redirects = 0; redirects <= 3; redirects++) {
        if (_inactive || expired || safeAvatarUri(uri.toString()) == null) {
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
          allowGif
              ? 'image/gif,image/jpeg,image/png,image/webp'
              : 'image/jpeg,image/png,image/webp',
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
            response.contentLength > byteLimit ||
            !{
              'image/jpeg',
              'image/png',
              'image/webp',
              if (allowGif) 'image/gif',
            }.contains(response.headers.contentType?.mimeType)) {
          await response.detachSocket().then((socket) => socket.destroy());
          throw const FormatException('avatar.response');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (bytes.length + chunk.length > byteLimit) {
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
        final meta = File(entity.path.replaceFirst(RegExp(r"\.bin$"), ".json"));
        total += stat.size + (await meta.exists() ? await meta.length() : 0);
        entries.add((entity, stat));
      }
    }
    entries.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var count = entries.length;
    for (final entry in entries) {
      if (total <= _diskLimit - _writeWindow && count <= 4096 - 64) break;
      count--;
      total -= entry.$2.size;
      await entry.$1.delete();
      final meta = File(entry.$1.path.replaceFirst(RegExp(r'\.bin$'), '.json'));
      if (await meta.exists()) {
        total -= await meta.length();
        await meta.delete();
      }
    }
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (path.endsWith(".part") ||
          (path.endsWith(".json") &&
              !await File(
                path.replaceFirst(RegExp(r"\.json$"), ".bin"),
              ).exists())) {
        if ((await entity.stat()).modified.isBefore(cutoff)) {
          await entity.delete();
        }
      }
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
    _animationBytes.clear();
    _retryAfter.clear();
  }
}
