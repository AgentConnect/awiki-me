import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'desktop_network_preference.dart';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_error_classifier.dart';
import '../../core/app_transport_failure.dart';

const windowsCaBundleVersion = 'mozilla-2026-08-13';
const windowsCaBundleAsset = 'assets/security/cacert-2026-08-13.pem';
const windowsCaBundleSha256 =
    'f66dff1bdf8f96060b8177976f8b7d9254bc89bc4db933d769f7384d28480bc9';

Future<Uint8List>? _bundleBytes;

http.Client createAppHttpClient() => (Platform.isMacOS || Platform.isWindows)
    ? DesktopRuntimeHttpClient()
    : http.Client();

Future<Uint8List> _readBundle(AssetBundle bundle) async {
  final data = await bundle.load(windowsCaBundleAsset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (sha256.convert(bytes).toString() != windowsCaBundleSha256) {
    throw const FormatException('trust_bundle_digest_mismatch');
  }
  return bytes;
}

/// Test seams are process-local; production retains Dart's built-in roots.
/// On Windows these are Mozilla-derived, not the Windows certificate store.
@visibleForTesting
Future<SecurityContext> createWindowsTrustContext({
  AssetBundle? bundle,
  SecurityContext? context,
}) async {
  final bytes = await (bundle != null
      ? _readBundle(bundle)
      : (_bundleBytes ??= _readBundle(rootBundle)));
  final trusted = context ?? SecurityContext(withTrustedRoots: true);
  trusted.setTrustedCertificatesBytes(bytes);
  return trusted;
}

Future<String> _appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    // Diagnostic metadata must never replace the original transport failure.
    return 'unknown';
  }
}

Future<http.Client> _buildClient() async {
  final context = await createWindowsTrustContext();
  return IOClient(HttpClient(context: context));
}

/// A per-owner client; only immutable CA bytes are shared between tenants.
/// Trust is ready before sending, so even non-idempotent requests send once.
class WindowsTrustHttpClient extends http.BaseClient {
  WindowsTrustHttpClient() : _build = _buildClient, _version = _appVersion;

  @visibleForTesting
  WindowsTrustHttpClient.forTesting({
    required Future<http.Client> Function() buildClient,
    Future<String> Function()? appVersion,
  }) : _build = buildClient,
       _version = appVersion ?? (() async => 'test');

  final Future<http.Client> Function() _build;
  final Future<String> Function() _version;
  Future<http.Client>? _initializing;
  http.Client? _client;
  bool _closed = false;

  Future<http.Client> _initialize() async {
    final client = await _build();
    if (_closed) {
      client.close();
    } else {
      _client = client;
    }
    return client;
  }

  Future<AppStructuredError> _failure(String code, Uri uri) async =>
      AppStructuredError(
        code: code,
        cause: AppTransportDiagnostic(
          code: code,
          host: uri.host,
          appVersion: await _version(),
          caVersion: windowsCaBundleVersion,
        ),
      );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client closed');
    final http.Client client;
    try {
      client = await (_initializing ??= _initialize());
    } catch (_) {
      throw await _failure(trustBundleFailureCode, request.url);
    }
    if (_closed) throw http.ClientException('Client closed');
    try {
      return await client.send(request);
    } on TlsException {
      throw await _failure(tlsHandshakeFailureCode, request.url);
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _client?.close();
    _client = null;
    // Pending initialization closes its client before any request is sent.
  }
}

/// Thin transport adapter; User Service authentication and protocol stay in Dart.
typedef DesktopNetworkSend =
    Future<core.AwikiNetworkResponse> Function({
      required String method,
      required String url,
      required Map<String, String> headers,
      required List<int> body,
      bool followRedirects,
      Future<void>? abortTrigger,
    });

class DesktopRuntimeHttpClient extends http.BaseClient {
  DesktopRuntimeHttpClient()
    : _initialize = DesktopNetworkPreference.instance.initialize,
      _transmit = core.AwikiDesktopNetwork.send;
  @visibleForTesting
  DesktopRuntimeHttpClient.forTesting({
    required Future<void> Function() initialize,
    required DesktopNetworkSend transmit,
  }) : _initialize = initialize,
       _transmit = transmit;
  final Future<void> Function() _initialize;
  final DesktopNetworkSend _transmit;
  bool _closed = false;
  final Set<Completer<void>> _aborters = {};
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) throw http.ClientException('Client closed');
    final abort = Completer<void>();
    _aborters.add(abort);
    if (request case http.Abortable(:final abortTrigger?)) {
      unawaited(
        abortTrigger.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    try {
      await _initialize();
      final body = await request.finalize().toBytes();
      if (_closed || abort.isCompleted) {
        throw http.RequestAbortedException(request.url);
      }
      final response = await _transmit(
        method: request.method,
        url: request.url.toString(),
        headers: request.headers,
        body: body,
        followRedirects: request.followRedirects,
        abortTrigger: abort.future,
      );
      Stream<List<int>> chunks() async* {
        try {
          yield* response.body;
        } catch (_) {
          if (abort.isCompleted) {
            throw http.RequestAbortedException(request.url);
          }
          rethrow;
        } finally {
          _aborters.remove(abort);
          await response.close();
        }
      }

      return http.StreamedResponse(
        chunks(),
        response.statusCode,
        headers: response.headers,
        contentLength: int.tryParse(response.headers['content-length'] ?? ''),
        request: request,
      );
    } catch (_) {
      _aborters.remove(abort);
      if (abort.isCompleted) throw http.RequestAbortedException(request.url);
      rethrow;
    }
  }

  @override
  void close() {
    _closed = true;
    for (final abort in _aborters.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    _aborters.clear();
  }
}

Future<String?> prepareWindowsNetworkCaBundle() async {
  final bytes = await (_bundleBytes ??= _readBundle(rootBundle));
  final root = await getApplicationSupportDirectory();
  final file = File('${root.path}/security/$windowsCaBundleVersion.pem');
  await file.parent.create(recursive: true);
  if (!await file.exists() ||
      sha256.convert(await file.readAsBytes()).toString() !=
          windowsCaBundleSha256) {
    await file.writeAsBytes(bytes, flush: true);
  }
  return file.path;
}
