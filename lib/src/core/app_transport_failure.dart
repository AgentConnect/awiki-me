import 'app_error_classifier.dart';

const tlsHandshakeFailureCode = 'transport.tls_handshake_failed';
const trustBundleFailureCode = 'transport.trust_bundle_invalid';

/// Only this allowlisted diagnostic may be copied from transport failures.
/// Never retain request paths, query strings, headers or exception bodies.
class AppTransportDiagnostic {
  const AppTransportDiagnostic({
    required this.code,
    required this.host,
    required this.appVersion,
    required this.caVersion,
  });

  final String code;
  final String host;
  final String appVersion;
  final String caVersion;

  @override
  String toString() =>
      'code=$code\nhost=$host\napp=$appVersion\nca_bundle=$caVersion';
}

String? appTransportDiagnostic(Object error) {
  if (error is AppStructuredError && error.cause is AppTransportDiagnostic) {
    return error.cause.toString();
  }
  return null;
}
