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

http.Client createAppHttpClient() =>
    Platform.isWindows ? WindowsTrustHttpClient() : http.Client();

Future<Uint8List> _readBundle(AssetBundle bundle) async {
  final data = await bundle.load(windowsCaBundleAsset);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (sha256.convert(bytes).toString() != windowsCaBundleSha256) {
    throw const FormatException('trust_bundle_digest_mismatch');
  }
  return bytes;
}

/// Test seams are process-local; production always retains the system roots.
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
