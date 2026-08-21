import 'dart:convert';

import 'package:awiki_im_core/awiki_im_core.dart' as core;

import '../../application/models/message_sync_diagnostics.dart';
import '../../application/ports/message_sync_core_port.dart';
import '../../core/app_error_classifier.dart';

class ImCoreMappedError {
  const ImCoreMappedError({
    required this.code,
    required this.message,
    this.field,
    this.statusCode,
    this.capability,
    this.serviceCode,
    this.serviceDataJson,
  });

  final String code;
  final String message;
  final String? field;
  final int? statusCode;
  final String? capability;
  final String? serviceCode;
  final String? serviceDataJson;

  bool get isUnsupported => code == 'unsupported_capability';

  bool get isDirectSyncBindingUnavailable =>
      code == 'service_error' && serviceCode == 'SYNC_THREAD_BINDING_REQUIRED';
}

class AwikiImCoreErrorMapper {
  const AwikiImCoreErrorMapper();

  ImCoreMappedError map(Object error) {
    if (error is core.AwikiImCoreException) {
      return ImCoreMappedError(
        code: error.code,
        message: _sanitize(error.message),
        field: error.field,
        statusCode: error.statusCode,
        capability: error.capability,
        serviceCode: error.serviceCode,
        serviceDataJson: error.serviceDataJson,
      );
    }
    if (error is UnsupportedError) {
      return ImCoreMappedError(
        code: 'unsupported_capability',
        message: _sanitize(
          error.message ?? 'IM Core capability is not available yet',
        ),
      );
    }
    return ImCoreMappedError(
      code: 'internal',
      message: _sanitize(error.toString()),
    );
  }

  Object appError(core.AwikiImCoreException error) {
    final code = _structuredAppErrorCode(error.serviceDataJson);
    return code == null ? error : AppStructuredError(code: code, cause: error);
  }

  UnsupportedError unsupported(String capability) {
    return UnsupportedError('IM Core $capability is not available yet');
  }

  MessageSyncCoreFailure messageSyncFailure(core.AwikiImCoreException error) {
    final mapped = map(error);
    final code = mapped.code.trim().toLowerCase();
    final serviceCode = mapped.serviceCode?.trim().toLowerCase();
    final authRejected =
        mapped.statusCode == 401 ||
        mapped.statusCode == 403 ||
        const <String>{
          'auth_required',
          'session_expired',
          'permission_denied',
        }.contains(code) ||
        const <String>{
          '1401',
          'anp.device_not_eligible',
          'anp.device_state_changed',
        }.contains(serviceCode);
    final category = authRejected
        ? AppMessageSyncFailureCategory.auth
        : switch (code) {
            'transport_unavailable' => AppMessageSyncFailureCategory.transport,
            'service_error' => AppMessageSyncFailureCategory.service,
            'local_state_unavailable' =>
              AppMessageSyncFailureCategory.localState,
            _ => AppMessageSyncFailureCategory.protocol,
          };
    return MessageSyncCoreFailure(
      category: category,
      code: _stableDiagnosticCode(
        mapped.serviceCode?.trim().isNotEmpty == true
            ? mapped.serviceCode!
            : mapped.code,
      ),
      httpStatus: mapped.statusCode,
    );
  }
}

String? _structuredAppErrorCode(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final value = decoded['awiki_code'];
    if (value is! String) return null;
    final code = value.trim();
    return _stableDiagnosticCode(code) == code ? code : null;
  } on FormatException {
    return null;
  }
}

String _stableDiagnosticCode(String code) {
  final trimmed = code.trim();
  final isSafe =
      trimmed.isNotEmpty &&
      trimmed.length <= 96 &&
      trimmed.codeUnits.every(
        (unit) =>
            (unit >= 48 && unit <= 57) ||
            (unit >= 65 && unit <= 90) ||
            (unit >= 97 && unit <= 122) ||
            unit == 45 ||
            unit == 46 ||
            unit == 95,
      );
  return isSafe ? trimmed : 'message_sync_failure';
}

String _sanitize(String input) {
  var output = input;
  final patterns = <RegExp>[
    RegExp(r'Bearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false),
    RegExp(r'Authorization:\s*[^\s,;]+', caseSensitive: false),
    RegExp(
      r'(token|jwt|private[_-]?key|signature)=([^\s,;]+)',
      caseSensitive: false,
    ),
  ];
  for (final pattern in patterns) {
    output = output.replaceAllMapped(pattern, (match) {
      final key = match.groupCount >= 1 ? match.group(1) : null;
      return key == null ? '<redacted>' : '$key=<redacted>';
    });
  }
  return output;
}
