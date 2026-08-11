import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

export 'attachment_image_dimensions.dart' show AttachmentImageDimensions;

import '../domain/entities/chat_message.dart';
import 'attachment_cache_service.dart';
import 'attachment_image_dimensions.dart';
import 'attachment_resource_reference.dart';
import 'models/attachment_models.dart';

enum AttachmentPreviewPhase { idle, loading, paused, ready, failed }

enum _AttachmentPreviewOrigin {
  authoritativeLocalSource,
  appCache,
  downloadedLocalSource,
}

typedef AttachmentPreviewBytesReader =
    Future<Uint8List> Function(String localPath);
typedef AttachmentDownloadCanceller = Future<bool> Function(String localPath);

class AttachmentPreviewSnapshot {
  const AttachmentPreviewSnapshot._({
    required this.phase,
    this.path,
    this.dimensions,
    this.error,
    this.stackTrace,
    this.receivedBytes,
    this.totalBytes,
  });

  const AttachmentPreviewSnapshot.idle({AttachmentImageDimensions? dimensions})
    : this._(phase: AttachmentPreviewPhase.idle, dimensions: dimensions);

  const AttachmentPreviewSnapshot.loading({
    AttachmentImageDimensions? dimensions,
    int? receivedBytes,
    int? totalBytes,
  }) : this._(
         phase: AttachmentPreviewPhase.loading,
         dimensions: dimensions,
         receivedBytes: receivedBytes,
         totalBytes: totalBytes,
       );

  const AttachmentPreviewSnapshot.paused({
    AttachmentImageDimensions? dimensions,
    int? receivedBytes,
    int? totalBytes,
  }) : this._(
         phase: AttachmentPreviewPhase.paused,
         dimensions: dimensions,
         receivedBytes: receivedBytes,
         totalBytes: totalBytes,
       );

  const AttachmentPreviewSnapshot.ready(
    String path, {
    AttachmentImageDimensions? dimensions,
  }) : this._(
         phase: AttachmentPreviewPhase.ready,
         path: path,
         dimensions: dimensions,
       );

  const AttachmentPreviewSnapshot.failed(
    Object error, {
    String? path,
    AttachmentImageDimensions? dimensions,
    StackTrace? stackTrace,
  }) : this._(
         phase: AttachmentPreviewPhase.failed,
         path: path,
         dimensions: dimensions,
         error: error,
         stackTrace: stackTrace,
       );

  final AttachmentPreviewPhase phase;
  final String? path;
  final AttachmentImageDimensions? dimensions;
  final Object? error;
  final StackTrace? stackTrace;
  final int? receivedBytes;
  final int? totalBytes;
}

class AttachmentPreviewHandle {
  AttachmentPreviewHandle._({
    required AttachmentPreviewSnapshot snapshot,
    required String? sourceLocalPath,
    required String? sourceObjectUri,
    required _AttachmentPreviewOrigin? readyOrigin,
    required void Function() onListenerDetached,
  }) : _snapshot = snapshot,
       _sourceLocalPath = sourceLocalPath,
       _sourceObjectUri = sourceObjectUri,
       _readyOrigin = readyOrigin,
       _changes = StreamController<AttachmentPreviewSnapshot>.broadcast(
         sync: true,
         onCancel: onListenerDetached,
       );

  AttachmentPreviewSnapshot get snapshot => _snapshot;

  Stream<AttachmentPreviewSnapshot> get changes => _changes.stream;

  AttachmentPreviewSnapshot _snapshot;
  final StreamController<AttachmentPreviewSnapshot> _changes;
  Future<String>? _inFlight;
  Future<void>? _dimensionProbeInFlight;
  int _generation = 0;
  String? _sourceLocalPath;
  String? _sourceObjectUri;
  _AttachmentPreviewOrigin? _readyOrigin;
  String? _rejectedDecodePath;
  _AttachmentPreviewOrigin? _rejectedDecodeOrigin;
  bool _bypassExistingCache = false;
  String? _dimensionProbePath;
  Timer? _progressTimer;
  bool _progressReadInFlight = false;
  String? _transferTargetPath;
  bool _cancellationRequested = false;
  Object? _deferredTransferError;
  StackTrace? _deferredTransferStackTrace;

  bool get _hasListeners => _changes.hasListener;

  void _replace(AttachmentPreviewSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_changes.isClosed) {
      _changes.add(snapshot);
    }
  }

  void _close() {
    _progressTimer?.cancel();
    if (!_changes.isClosed) {
      unawaited(_changes.close());
    }
  }
}

class AttachmentPreviewService {
  AttachmentPreviewService({
    required this.cache,
    this.imageDimensionProbe = const NoopAttachmentImageDimensionProbe(),
    AttachmentPreviewBytesReader? bytesReader,
    this.cancelDownload,
    this.maxRetainedEntries = 512,
  }) : _bytesReader = bytesReader ?? _readLocalFileBytes,
       assert(maxRetainedEntries > 0);

  final AttachmentCacheService cache;
  final AttachmentImageDimensionProbe imageDimensionProbe;
  final AttachmentPreviewBytesReader _bytesReader;
  final AttachmentDownloadCanceller? cancelDownload;

  /// Maximum inactive handles retained in memory. Handles with listeners or an
  /// active resolution may temporarily exceed this value; completion and the
  /// last listener detaching both trigger cleanup back to the limit.
  final int maxRetainedEntries;

  final LinkedHashMap<String, AttachmentPreviewHandle> _entries =
      LinkedHashMap<String, AttachmentPreviewHandle>();
  bool _disposed = false;
  bool _trimScheduled = false;

  AttachmentPreviewHandle previewHandleFor(ChatMessage message) {
    if (_disposed) {
      throw StateError('AttachmentPreviewService is disposed');
    }
    final attachment = message.attachment;
    if (attachment == null) {
      throw const AttachmentUnavailableException();
    }

    final identity = _previewIdentity(message);
    var handle = _entries.remove(identity);
    if (handle == null) {
      final localPath = _normalized(attachment.localPath);
      handle = AttachmentPreviewHandle._(
        snapshot: localPath == null
            ? const AttachmentPreviewSnapshot.idle()
            : AttachmentPreviewSnapshot.ready(localPath),
        sourceLocalPath: localPath,
        sourceObjectUri: _normalized(attachment.objectUri),
        readyOrigin: localPath == null
            ? null
            : _AttachmentPreviewOrigin.authoritativeLocalSource,
        onListenerDetached: _scheduleTrim,
      );
    } else {
      _reconcileSources(handle, message);
    }
    _entries[identity] = handle;
    final readyPath = handle.snapshot.path;
    if (handle.snapshot.phase == AttachmentPreviewPhase.ready &&
        readyPath != null) {
      _maybeProbeImageDimensions(
        handle: handle,
        message: message,
        path: readyPath,
      );
    }
    _trimEntries(protectedHandle: handle);
    return handle;
  }

  Future<String> previewPathFor({
    required ChatMessage message,
    required Future<AttachmentDownloadResult> Function() download,
    Future<AttachmentDownloadResult> Function(String localPath)? downloadToPath,
  }) {
    final attachment = message.attachment;
    if (attachment == null) {
      return Future<String>.error(const AttachmentUnavailableException());
    }

    final handle = previewHandleFor(message);
    final inFlight = handle._inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final generation = handle._generation;
    handle
      .._cancellationRequested = false
      .._deferredTransferError = null
      .._deferredTransferStackTrace = null;
    final currentPath = handle.snapshot.path;
    final currentOrigin = handle._readyOrigin;
    final rejectedDecodePath = handle._rejectedDecodePath;
    final rejectedDecodeOrigin = handle._rejectedDecodeOrigin;
    final bypassExistingCache = handle._bypassExistingCache;
    final preservesRejectedLocalState =
        handle.snapshot.phase == AttachmentPreviewPhase.failed &&
        rejectedDecodeOrigin ==
            _AttachmentPreviewOrigin.authoritativeLocalSource &&
        _resourceIdentity(handle._sourceLocalPath) ==
            _resourceIdentity(rejectedDecodePath);
    if (handle.snapshot.phase != AttachmentPreviewPhase.ready &&
        !preservesRejectedLocalState) {
      handle._replace(
        AttachmentPreviewSnapshot.loading(
          dimensions: handle.snapshot.dimensions,
        ),
      );
    }

    late final Future<String> resolution;
    resolution =
        _resolvePreviewPath(
              message: message,
              currentPath: currentPath,
              currentOrigin: currentOrigin,
              rejectedDecodePath: rejectedDecodePath,
              rejectedDecodeOrigin: rejectedDecodeOrigin,
              bypassExistingCache: bypassExistingCache,
              download: download,
              downloadToPath: downloadToPath,
              isActive: () => _isCurrent(handle, generation),
              onRemoteResolutionStarted: () {
                if (_isCurrent(handle, generation) &&
                    handle.snapshot.phase != AttachmentPreviewPhase.loading) {
                  handle._replace(
                    AttachmentPreviewSnapshot.loading(
                      dimensions: handle.snapshot.dimensions,
                    ),
                  );
                }
              },
              onTransferTargetPrepared: (path) {
                if (_isCurrent(handle, generation)) {
                  handle._transferTargetPath = path;
                  _startProgressPolling(
                    handle: handle,
                    stagedPath: path,
                    totalBytes: attachment.sizeBytes,
                    generation: generation,
                  );
                }
              },
            )
            .then<String>(
              (resolved) {
                if (!_isCurrent(handle, generation)) {
                  throw const AttachmentPreviewResolutionInvalidatedException();
                }
                if (_isCurrent(handle, generation) &&
                    resolved.publishReady &&
                    (resolved.isFresh ||
                        !_isRejectedDecodePath(
                          handle,
                          path: resolved.path,
                          origin: resolved.origin,
                        ))) {
                  final dimensions = handle.snapshot.dimensions;
                  handle
                    .._readyOrigin = resolved.origin
                    .._rejectedDecodePath = null
                    .._rejectedDecodeOrigin = null
                    .._bypassExistingCache = false
                    .._replace(
                      AttachmentPreviewSnapshot.ready(
                        resolved.path,
                        dimensions: dimensions,
                      ),
                    );
                  _maybeProbeImageDimensions(
                    handle: handle,
                    message: message,
                    path: resolved.path,
                  );
                }
                return resolved.path;
              },
              onError: (Object error, StackTrace stackTrace) {
                if (_isCurrent(handle, generation)) {
                  if (handle._cancellationRequested) {
                    handle
                      .._deferredTransferError = error
                      .._deferredTransferStackTrace = stackTrace;
                  } else {
                    handle._replace(
                      AttachmentPreviewSnapshot.failed(
                        error,
                        path: handle.snapshot.path,
                        dimensions: handle.snapshot.dimensions,
                        stackTrace: stackTrace,
                      ),
                    );
                  }
                }
                Error.throwWithStackTrace(error, stackTrace);
              },
            )
            .whenComplete(() {
              if (identical(handle._inFlight, resolution)) {
                handle._progressTimer?.cancel();
                handle._progressTimer = null;
                handle._transferTargetPath = null;
                handle._inFlight = null;
              }
              _scheduleTrim();
            });
    handle._inFlight = resolution;
    return resolution;
  }

  Future<bool> cancelPreviewDownload(ChatMessage message) async {
    if (_disposed || message.attachment == null || cancelDownload == null) {
      return false;
    }
    final handle = _entries[_previewIdentity(message)];
    final targetPath = handle?._transferTargetPath;
    if (handle == null || handle._inFlight == null || targetPath == null) {
      return false;
    }
    final snapshot = handle.snapshot;
    handle
      .._cancellationRequested = true
      .._replace(
        AttachmentPreviewSnapshot.paused(
          dimensions: snapshot.dimensions,
          receivedBytes: snapshot.receivedBytes,
          totalBytes: snapshot.totalBytes,
        ),
      );
    final bool cancelled;
    try {
      cancelled = await cancelDownload!(targetPath);
    } on Object {
      _restoreAfterRejectedCancellation(handle, snapshot);
      rethrow;
    }
    if (!cancelled) {
      _restoreAfterRejectedCancellation(handle, snapshot);
      return false;
    }
    if (_disposed || handle._inFlight == null) {
      handle
        .._cancellationRequested = false
        .._deferredTransferError = null
        .._deferredTransferStackTrace = null;
      return true;
    }
    handle
      .._generation += 1
      .._cancellationRequested = false
      .._deferredTransferError = null
      .._deferredTransferStackTrace = null
      .._progressTimer?.cancel()
      .._progressTimer = null
      .._replace(handle.snapshot);
    return true;
  }

  void _restoreAfterRejectedCancellation(
    AttachmentPreviewHandle handle,
    AttachmentPreviewSnapshot previous,
  ) {
    if (_disposed) return;
    final deferredError = handle._deferredTransferError;
    final deferredStackTrace = handle._deferredTransferStackTrace;
    handle
      .._cancellationRequested = false
      .._deferredTransferError = null
      .._deferredTransferStackTrace = null;
    if (deferredError != null) {
      handle._replace(
        AttachmentPreviewSnapshot.failed(
          deferredError,
          path: previous.path,
          dimensions: previous.dimensions,
          stackTrace: deferredStackTrace,
        ),
      );
    } else if (handle._inFlight != null) {
      handle._replace(previous);
    }
  }

  Future<Uint8List> readPreviewBytes(String previewPath) async {
    final reference = AttachmentResourceReference.parse(previewPath);
    final localPath = reference.localPath;
    if (!reference.isLocalFile || localPath == null) {
      throw const AttachmentUnavailableException();
    }
    try {
      final bytes = await _bytesReader(localPath);
      if (bytes.isEmpty) {
        throw StateError('attachment_copy_empty');
      }
      return bytes;
    } on FileSystemException {
      throw const AttachmentUnavailableException();
    }
  }

  void reportPreviewDecodeFailure({
    required ChatMessage message,
    required String path,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_disposed || message.attachment == null) {
      return;
    }
    final handle = _entries[_previewIdentity(message)];
    if (handle == null) {
      return;
    }
    final currentPath = _resourceIdentity(handle.snapshot.path);
    if (handle.snapshot.phase != AttachmentPreviewPhase.ready ||
        currentPath != _resourceIdentity(path) ||
        handle._readyOrigin == null) {
      return;
    }
    final readyOrigin = handle._readyOrigin!;
    if (readyOrigin != _AttachmentPreviewOrigin.authoritativeLocalSource) {
      handle
        .._generation += 1
        .._inFlight = null
        .._dimensionProbeInFlight = null
        .._dimensionProbePath = null;
    }
    handle
      .._rejectedDecodePath = currentPath
      .._rejectedDecodeOrigin = readyOrigin
      .._bypassExistingCache =
          readyOrigin != _AttachmentPreviewOrigin.authoritativeLocalSource
      .._replace(
        AttachmentPreviewSnapshot.failed(
          error ?? AttachmentPreviewDecodeException(path),
          path: path,
          dimensions: handle.snapshot.dimensions,
          stackTrace: stackTrace,
        ),
      );
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final handle in _entries.values) {
      final targetPath = handle._transferTargetPath;
      if (targetPath != null) _cancelTransferBestEffort(targetPath);
      handle._close();
    }
    _entries.clear();
  }

  Future<_AttachmentPreviewResolution> _resolvePreviewPath({
    required ChatMessage message,
    required String? currentPath,
    required _AttachmentPreviewOrigin? currentOrigin,
    required String? rejectedDecodePath,
    required _AttachmentPreviewOrigin? rejectedDecodeOrigin,
    required bool bypassExistingCache,
    required Future<AttachmentDownloadResult> Function() download,
    required Future<AttachmentDownloadResult> Function(String localPath)?
    downloadToPath,
    required bool Function() isActive,
    required void Function() onRemoteResolutionStarted,
    required void Function(String path) onTransferTargetPrepared,
  }) async {
    _ensureResolutionActive(isActive);
    final attachment = message.attachment!;
    final localPath = await availableAttachmentPath(attachment.localPath);
    _ensureResolutionActive(isActive);
    if (localPath != null) {
      final rejected = _matchesRejectedDecodePath(
        path: localPath,
        origin: _AttachmentPreviewOrigin.authoritativeLocalSource,
        rejectedPath: rejectedDecodePath,
        rejectedOrigin: rejectedDecodeOrigin,
      );
      return _AttachmentPreviewResolution(
        path: localPath,
        origin: _AttachmentPreviewOrigin.authoritativeLocalSource,
        publishReady: !rejected,
      );
    }

    if (!bypassExistingCache && currentOrigin != null) {
      final availableCurrentPath = await availableAttachmentPath(currentPath);
      _ensureResolutionActive(isActive);
      if (availableCurrentPath != null &&
          !_matchesRejectedDecodePath(
            path: availableCurrentPath,
            origin: currentOrigin,
            rejectedPath: rejectedDecodePath,
            rejectedOrigin: rejectedDecodeOrigin,
          )) {
        return _AttachmentPreviewResolution(
          path: availableCurrentPath,
          origin: currentOrigin,
        );
      }
    }

    final messageId = _stableMessageId(message);
    if (!bypassExistingCache) {
      final cachedPath = await cache.lookup(
        messageId: messageId,
        attachmentId: attachment.attachmentId,
      );
      _ensureResolutionActive(isActive);
      final availableCachedPath = await availableAttachmentPath(cachedPath);
      _ensureResolutionActive(isActive);
      if (availableCachedPath != null &&
          !_matchesRejectedDecodePath(
            path: availableCachedPath,
            origin: _AttachmentPreviewOrigin.appCache,
            rejectedPath: rejectedDecodePath,
            rejectedOrigin: rejectedDecodeOrigin,
          )) {
        return _AttachmentPreviewResolution(
          path: availableCachedPath,
          origin: _AttachmentPreviewOrigin.appCache,
        );
      }
    }

    _ensureResolutionActive(isActive);
    onRemoteResolutionStarted();
    final String? stagedPath;
    final AttachmentDownloadResult result;
    if (downloadToPath == null) {
      stagedPath = null;
      result = await download();
    } else {
      stagedPath = await cache.prepareDownloadedFile(
        messageId: messageId,
        attachmentId: attachment.attachmentId,
      );
      _ensureResolutionActive(isActive);
      onTransferTargetPrepared(stagedPath);
      result = await downloadToPath(stagedPath);
    }
    _ensureResolutionActive(isActive);
    final downloadedPath = await availableAttachmentPath(result.localPath);
    _ensureResolutionActive(isActive);
    if (downloadedPath != null) {
      if (stagedPath != null) {
        final path = await cache.commitDownloadedFileIfCurrent(
          messageId: messageId,
          attachmentId: attachment.attachmentId,
          filename: result.filename ?? attachment.filename,
          mimeType: result.mimeType ?? attachment.mimeType,
          stagedPath: downloadedPath,
          isCurrent: isActive,
        );
        if (path == null) {
          throw const AttachmentPreviewResolutionInvalidatedException();
        }
        _ensureResolutionActive(isActive);
        return _AttachmentPreviewResolution(
          path: path,
          origin: _AttachmentPreviewOrigin.appCache,
          isFresh: true,
        );
      }
      return _AttachmentPreviewResolution(
        path: downloadedPath,
        origin: _AttachmentPreviewOrigin.downloadedLocalSource,
        isFresh: true,
      );
    }

    final bytes = result.bytes;
    if (bytes == null) {
      throw const AttachmentUnavailableException();
    }
    _ensureResolutionActive(isActive);
    final path = await cache.cacheDownloadedBytesIfCurrent(
      messageId: messageId,
      attachmentId: attachment.attachmentId,
      filename: result.filename ?? attachment.filename,
      mimeType: result.mimeType ?? attachment.mimeType,
      bytes: bytes,
      isCurrent: isActive,
    );
    if (path == null) {
      throw const AttachmentPreviewResolutionInvalidatedException();
    }
    _ensureResolutionActive(isActive);
    return _AttachmentPreviewResolution(
      path: path,
      origin: _AttachmentPreviewOrigin.appCache,
      isFresh: true,
    );
  }

  void _startProgressPolling({
    required AttachmentPreviewHandle handle,
    required String stagedPath,
    required int? totalBytes,
    required int generation,
  }) {
    handle._progressTimer?.cancel();
    Future<void> publish() async {
      if (!_isCurrent(handle, generation) || handle._progressReadInFlight) {
        return;
      }
      handle._progressReadInFlight = true;
      try {
        final partial = File('$stagedPath$attachmentResumablePartialSuffix');
        final staged = File(stagedPath);
        final int receivedBytes;
        if (await partial.exists()) {
          receivedBytes = await partial.length();
        } else if (await staged.exists()) {
          receivedBytes = await staged.length();
        } else {
          receivedBytes = 0;
        }
        if (_isCurrent(handle, generation) &&
            handle.snapshot.phase == AttachmentPreviewPhase.loading &&
            handle.snapshot.receivedBytes != receivedBytes) {
          handle._replace(
            AttachmentPreviewSnapshot.loading(
              dimensions: handle.snapshot.dimensions,
              receivedBytes: receivedBytes,
              totalBytes: totalBytes,
            ),
          );
        }
      } on FileSystemException {
        // The Core owns creation and atomic renames; a polling miss is normal.
      } finally {
        handle._progressReadInFlight = false;
      }
    }

    unawaited(publish());
    handle._progressTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(publish()),
    );
  }

  static Future<String?> availableAttachmentPath(
    String? pathOrUri, {
    bool? windows,
  }) async {
    final value = pathOrUri?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final reference = AttachmentResourceReference.parse(
      value,
      windows: windows,
    );
    if (!reference.isLocalFile) {
      return value;
    }
    final file = File(reference.localPath!);
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  static Future<Uint8List> _readLocalFileBytes(String localPath) {
    return File(localPath).readAsBytes();
  }

  String _stableMessageId(ChatMessage message) {
    final remoteId = message.remoteId?.trim();
    if (remoteId != null && remoteId.isNotEmpty) {
      return remoteId;
    }
    return message.localId.trim();
  }

  String _previewIdentity(ChatMessage message) {
    final attachment = message.attachment!;
    final conversation =
        _normalized(message.conversationId) ??
        _normalized(message.threadId) ??
        'unknown-conversation';
    final attachmentIdentity =
        _normalized(attachment.attachmentId) ??
        _normalized(attachment.objectUri) ??
        '${_stableMessageId(message)}:${attachment.filename.trim()}';
    return '$conversation\x1f$attachmentIdentity';
  }

  void _reconcileSources(AttachmentPreviewHandle handle, ChatMessage message) {
    final attachment = message.attachment!;
    final localPath = _normalized(attachment.localPath);
    final objectUri = _normalized(attachment.objectUri);

    if (localPath == handle._sourceLocalPath &&
        objectUri == handle._sourceObjectUri) {
      return;
    }
    if (localPath != null && localPath == handle._sourceLocalPath) {
      handle._sourceObjectUri = objectUri;
      return;
    }

    final transferTargetPath = handle._transferTargetPath;
    if (transferTargetPath != null) {
      _cancelTransferBestEffort(transferTargetPath);
    }

    final provisionalDimensions = handle.snapshot.dimensions;
    handle
      .._sourceLocalPath = localPath
      .._sourceObjectUri = objectUri
      .._generation += 1
      .._inFlight = null
      .._transferTargetPath = null
      .._cancellationRequested = false
      .._deferredTransferError = null
      .._deferredTransferStackTrace = null
      .._dimensionProbeInFlight = null
      .._dimensionProbePath = null
      .._rejectedDecodePath = null
      .._rejectedDecodeOrigin = null;
    if (localPath != null) {
      handle
        .._readyOrigin = _AttachmentPreviewOrigin.authoritativeLocalSource
        .._bypassExistingCache = false
        .._replace(
          AttachmentPreviewSnapshot.ready(
            localPath,
            dimensions: provisionalDimensions,
          ),
        );
    } else {
      handle
        .._readyOrigin = null
        .._bypassExistingCache = true
        .._replace(
          AttachmentPreviewSnapshot.idle(dimensions: provisionalDimensions),
        );
    }
  }

  bool _isCurrent(AttachmentPreviewHandle handle, int generation) {
    return !_disposed && handle._generation == generation;
  }

  void _cancelTransferBestEffort(String localPath) {
    final cancel = cancelDownload;
    if (cancel == null) return;
    try {
      unawaited(cancel(localPath).catchError((Object _) => false));
    } on Object {
      // Provider disposal can invalidate the host callback synchronously.
    }
  }

  void _maybeProbeImageDimensions({
    required AttachmentPreviewHandle handle,
    required ChatMessage message,
    required String path,
  }) {
    final attachment = message.attachment;
    if (_disposed ||
        attachment == null ||
        !isSupportedAttachmentPreviewImage(attachment)) {
      return;
    }
    final localPath = AttachmentResourceReference.parse(path).localPath;
    if (localPath == null) {
      return;
    }
    final pathIdentity = _resourceIdentity(localPath)!;
    if (_resourceIdentity(handle._dimensionProbePath) == pathIdentity) {
      return;
    }

    handle._dimensionProbePath = pathIdentity;
    final generation = handle._generation;
    late final Future<void> probe;
    probe = imageDimensionProbe
        .probe(localPath)
        .then<void>((dimensions) {
          if (dimensions == null ||
              !_isCurrent(handle, generation) ||
              _resourceIdentity(handle._dimensionProbePath) != pathIdentity ||
              _resourceIdentity(handle.snapshot.path) != pathIdentity) {
            return;
          }
          final snapshot = handle.snapshot;
          if (snapshot.phase == AttachmentPreviewPhase.ready) {
            handle._replace(
              AttachmentPreviewSnapshot.ready(
                snapshot.path!,
                dimensions: dimensions,
              ),
            );
          } else if (snapshot.phase == AttachmentPreviewPhase.failed) {
            handle._replace(
              AttachmentPreviewSnapshot.failed(
                snapshot.error!,
                path: snapshot.path,
                dimensions: dimensions,
                stackTrace: snapshot.stackTrace,
              ),
            );
          }
        }, onError: (Object _, StackTrace _) {})
        .whenComplete(() {
          if (identical(handle._dimensionProbeInFlight, probe)) {
            handle._dimensionProbeInFlight = null;
          }
          _scheduleTrim();
        });
    handle._dimensionProbeInFlight = probe;
  }

  void _scheduleTrim() {
    if (_disposed || _trimScheduled) {
      return;
    }
    _trimScheduled = true;
    scheduleMicrotask(() {
      _trimScheduled = false;
      if (!_disposed) {
        _trimEntries();
      }
    });
  }

  void _trimEntries({AttachmentPreviewHandle? protectedHandle}) {
    while (_entries.length > maxRetainedEntries) {
      String? evictionKey;
      for (final entry in _entries.entries) {
        final handle = entry.value;
        if (!identical(handle, protectedHandle) &&
            handle._inFlight == null &&
            handle._dimensionProbeInFlight == null &&
            !handle._hasListeners) {
          evictionKey = entry.key;
          break;
        }
      }
      if (evictionKey == null) {
        return;
      }
      _entries.remove(evictionKey)?._close();
    }
  }

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static bool _matchesRejectedDecodePath({
    required String path,
    required _AttachmentPreviewOrigin origin,
    required String? rejectedPath,
    required _AttachmentPreviewOrigin? rejectedOrigin,
  }) {
    return rejectedOrigin == origin &&
        _resourceIdentity(rejectedPath) == _resourceIdentity(path);
  }

  static bool _isRejectedDecodePath(
    AttachmentPreviewHandle handle, {
    required String path,
    required _AttachmentPreviewOrigin origin,
  }) {
    return _matchesRejectedDecodePath(
      path: path,
      origin: origin,
      rejectedPath: handle._rejectedDecodePath,
      rejectedOrigin: handle._rejectedDecodeOrigin,
    );
  }

  static void _ensureResolutionActive(bool Function() isActive) {
    if (!isActive()) {
      throw const AttachmentPreviewResolutionInvalidatedException();
    }
  }

  static String? _resourceIdentity(String? value) {
    final normalized = _normalized(value);
    if (normalized == null) {
      return null;
    }
    return AttachmentResourceReference.parse(normalized).localPath ??
        normalized;
  }
}

class AttachmentUnavailableException implements Exception {
  const AttachmentUnavailableException();

  @override
  String toString() => 'AttachmentUnavailableException';
}

class AttachmentPreviewDecodeException implements Exception {
  const AttachmentPreviewDecodeException(this.path);

  final String path;

  @override
  String toString() => 'AttachmentPreviewDecodeException($path)';
}

class AttachmentPreviewResolutionInvalidatedException implements Exception {
  const AttachmentPreviewResolutionInvalidatedException();

  @override
  String toString() => 'AttachmentPreviewResolutionInvalidatedException';
}

class _AttachmentPreviewResolution {
  const _AttachmentPreviewResolution({
    required this.path,
    required this.origin,
    this.publishReady = true,
    this.isFresh = false,
  });

  final String path;
  final _AttachmentPreviewOrigin origin;
  final bool publishReady;
  final bool isFresh;
}
