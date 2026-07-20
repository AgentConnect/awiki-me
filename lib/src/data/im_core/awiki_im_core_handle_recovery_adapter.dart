// [INPUT]: Purpose-bound SMS OTPs, the local Recovery Core facade, and one tenant domain.
// [OUTPUT]: Secret-free Handle Recovery progress and activation candidates for AWiki Me.
// [POS]: Production Recovery adapter; credentials are method-local and immediately consumed by Core.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:http/http.dart' as http;

import '../../application/models/app_session.dart';
import '../../application/models/handle_recovery_completion.dart';
import '../../application/ports/handle_recovery_port.dart';
import '../../domain/entities/handle_recovery.dart';
import 'awiki_im_core_mappers.dart';
import 'awiki_im_core_runtime.dart';

typedef AwikiImCoreInstance = Future<core.AwikiImCore> Function();
typedef AwikiImCoreLocalHandleRecoverySessions =
    Future<List<core.HandleRecoveryProgress>> Function();
typedef AwikiImCoreBeginHandleRecovery =
    Future<core.HandleRecoveryProgress> Function({
      required String handle,
      required core.HandleRecoveryBeginVerificationGrant verificationGrant,
    });
typedef AwikiImCorePollHandleRecovery =
    Future<core.HandleRecoveryProgress> Function(String recoverySessionId);
typedef AwikiImCoreCancelHandleRecovery =
    Future<core.HandleRecoveryCancelResult> Function({
      required core.IdentitySelector oldIdentity,
      required String recoverySessionId,
      required bool userPresenceConfirmed,
    });
typedef AwikiImCoreFinalizeHandleRecovery =
    Future<core.HandleRecoveryFinalizeResult> Function({
      required String recoverySessionId,
      required core.HandleRecoveryFinalizeVerificationGrant verificationGrant,
      required bool userPresenceConfirmed,
    });
typedef AwikiImCoreResumeHandleRecoveryActivation =
    Future<core.IdentitySummary> Function(String recoverySessionId);
typedef AwikiImCoreMarkHandleRecoveryActivationComplete =
    Future<void> Function(String recoverySessionId);
typedef RecoveryIdempotencyScopeFactory =
    String Function(String purpose, String? recoverySessionId);

/// Same-domain account verification plus the secret-free Recovery Core API.
class AwikiImCoreHandleRecoveryAdapter implements HandleRecoveryPort {
  AwikiImCoreHandleRecoveryAdapter({
    required AwikiImCoreRuntime runtime,
    required String userServiceUrl,
    required String targetHandleDomain,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
  }) : this.withCoreInstance(
         coreInstance: runtime.coreInstance,
         userServiceUrl: userServiceUrl,
         targetHandleDomain: targetHandleDomain,
         httpClient: httpClient,
         timeout: timeout,
         mappers: mappers,
       );

  AwikiImCoreHandleRecoveryAdapter.withCoreInstance({
    required AwikiImCoreInstance coreInstance,
    required this.userServiceUrl,
    required String targetHandleDomain,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
    AwikiImCoreMappers mappers = const AwikiImCoreMappers(),
    AwikiImCoreLocalHandleRecoverySessions? localSessions,
    AwikiImCoreBeginHandleRecovery? begin,
    AwikiImCorePollHandleRecovery? poll,
    AwikiImCoreCancelHandleRecovery? cancel,
    AwikiImCoreFinalizeHandleRecovery? finalize,
    AwikiImCoreResumeHandleRecoveryActivation? resumeActivation,
    AwikiImCoreMarkHandleRecoveryActivationComplete? markActivationComplete,
    RecoveryIdempotencyScopeFactory? idempotencyScopeFactory,
  }) : targetHandleDomain = _normalizeDomain(targetHandleDomain),
       _httpClient = httpClient ?? http.Client(),
       _timeout = timeout,
       _mappers = mappers,
       _localSessions =
           localSessions ??
           (() async => (await coreInstance()).localHandleRecoverySessions()),
       _begin =
           begin ??
           (({required handle, required verificationGrant}) async =>
               (await coreInstance()).beginHandleRecovery(
                 handle: handle,
                 verificationGrant: verificationGrant,
               )),
       _poll =
           poll ??
           ((recoverySessionId) async =>
               (await coreInstance()).pollHandleRecovery(recoverySessionId)),
       _cancel =
           cancel ??
           (({
             required oldIdentity,
             required recoverySessionId,
             required userPresenceConfirmed,
           }) async => (await coreInstance()).cancelHandleRecovery(
             oldIdentity: oldIdentity,
             recoverySessionId: recoverySessionId,
             userPresenceConfirmed: userPresenceConfirmed,
           )),
       _finalize =
           finalize ??
           (({
             required recoverySessionId,
             required verificationGrant,
             required userPresenceConfirmed,
           }) async => (await coreInstance()).finalizeHandleRecovery(
             recoverySessionId: recoverySessionId,
             verificationGrant: verificationGrant,
             userPresenceConfirmed: userPresenceConfirmed,
           )),
       _resumeActivation =
           resumeActivation ??
           ((recoverySessionId) async => (await coreInstance())
               .resumeHandleRecoveryActivation(recoverySessionId)),
       _markActivationComplete =
           markActivationComplete ??
           ((recoverySessionId) async => (await coreInstance())
               .markHandleRecoveryActivationComplete(recoverySessionId)),
       _idempotencyScopeFactory =
           idempotencyScopeFactory ?? _newRecoveryIdempotencyScope;

  static const String accountVerificationExchangePath =
      '/user-service/auth/account-verification/exchange';
  static const String smsCodePath = '/user-service/auth/sms-codes';
  static const String beginPurpose = 'awiki.device.recovery.begin.v1';
  static const String finalizePurpose = 'awiki.device.recovery.finalize.v1';

  final String userServiceUrl;
  final String targetHandleDomain;
  final http.Client _httpClient;
  final Duration _timeout;
  final AwikiImCoreMappers _mappers;
  final AwikiImCoreLocalHandleRecoverySessions _localSessions;
  final AwikiImCoreBeginHandleRecovery _begin;
  final AwikiImCorePollHandleRecovery _poll;
  final AwikiImCoreCancelHandleRecovery _cancel;
  final AwikiImCoreFinalizeHandleRecovery _finalize;
  final AwikiImCoreResumeHandleRecoveryActivation _resumeActivation;
  final AwikiImCoreMarkHandleRecoveryActivationComplete _markActivationComplete;
  final RecoveryIdempotencyScopeFactory _idempotencyScopeFactory;

  @override
  Future<void> sendRecoveryBeginSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
  }) {
    final target = _target(handle, handleDomain);
    return _sendSmsOtp(phone: phone, purpose: beginPurpose, target: target);
  }

  @override
  Future<void> sendRecoveryFinalizeSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
    required String recoverySessionId,
  }) {
    final target = _target(handle, handleDomain);
    return _sendSmsOtp(
      phone: phone,
      purpose: finalizePurpose,
      target: target,
      recoverySessionId: _required(recoverySessionId, 'recoverySessionId'),
    );
  }

  @override
  Future<List<HandleRecoveryProgress>> localHandleRecoverySessions() async {
    final sessions = await _localSessions();
    return sessions.map(_progressFromCore).toList(growable: false);
  }

  @override
  Future<HandleRecoveryProgress> beginHandleRecoveryWithSms({
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async {
    final target = _target(handle, handleDomain);
    final token = await _exchangeSmsOtp(
      phone: phone,
      otp: otp,
      purpose: beginPurpose,
      target: target,
      idempotencyScope: _idempotencyScopeFactory(beginPurpose, null),
      credentialField: 'account_verification_token',
      forbiddenCredentialField: 'reconfirmation_token',
    );
    final grant = core.HandleRecoveryBeginVerificationGrant.fromToken(token);
    return _progressFromCore(
      await _begin(handle: target.canonicalHandle, verificationGrant: grant),
    );
  }

  @override
  Future<HandleRecoveryProgress> pollHandleRecovery(
    String recoverySessionId,
  ) async {
    return _progressFromCore(
      await _poll(_required(recoverySessionId, 'recoverySessionId')),
    );
  }

  @override
  Future<HandleRecoveryCancelResult> cancelHandleRecovery({
    required String selector,
    required String recoverySessionId,
  }) async {
    final oldDid = _required(selector, 'selector');
    if (!oldDid.startsWith('did:')) {
      throw const HandleRecoveryTransportException('invalid_old_identity');
    }
    final result = await _cancel(
      oldIdentity: core.IdentitySelector.did(oldDid),
      recoverySessionId: _required(recoverySessionId, 'recoverySessionId'),
      userPresenceConfirmed: true,
    );
    return HandleRecoveryCancelResult(
      recoverySessionId: result.recoverySessionId,
      phase: _phaseFromCore(result.phase),
    );
  }

  @override
  Future<HandleRecoveryCompletion> finalizeHandleRecoveryWithSms({
    required String recoverySessionId,
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  }) async {
    final sessionId = _required(recoverySessionId, 'recoverySessionId');
    final target = _target(handle, handleDomain);
    final token = await _exchangeSmsOtp(
      phone: phone,
      otp: otp,
      purpose: finalizePurpose,
      target: target,
      recoverySessionId: sessionId,
      idempotencyScope: _idempotencyScopeFactory(finalizePurpose, sessionId),
      credentialField: 'reconfirmation_token',
      forbiddenCredentialField: 'account_verification_token',
    );
    final grant = core.HandleRecoveryFinalizeVerificationGrant.fromToken(token);
    final result = await _finalize(
      recoverySessionId: sessionId,
      verificationGrant: grant,
      userPresenceConfirmed: true,
    );
    final progress = _progressFromCore(result.progress);
    return HandleRecoveryCompletion(
      progress: progress,
      session: _activationCandidate(result.identity),
    );
  }

  @override
  Future<AppSession> resumeRecoveryActivation(String recoverySessionId) async {
    final identity = await _resumeActivation(
      _required(recoverySessionId, 'recoverySessionId'),
    );
    return _activationCandidate(identity);
  }

  @override
  Future<void> markRecoveryActivationComplete(String recoverySessionId) {
    return _markActivationComplete(
      _required(recoverySessionId, 'recoverySessionId'),
    );
  }

  Future<void> _sendSmsOtp({
    required String phone,
    required String purpose,
    required _RecoveryTarget target,
    String? recoverySessionId,
  }) async {
    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(userServiceUrl).resolve(smsCodePath),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              'phone': _required(phone, 'phone'),
              'purpose': purpose,
              'target_handle': target.handle,
              'target_handle_domain': target.domain,
              if (recoverySessionId != null)
                'recovery_session_id': recoverySessionId,
            }),
          )
          .timeout(_timeout);
    } on Object {
      throw const HandleRecoveryTransportException('sms_code_network');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HandleRecoveryTransportException(
        'sms_code_http_${response.statusCode}',
      );
    }
  }

  Future<String> _exchangeSmsOtp({
    required String phone,
    required String otp,
    required String purpose,
    required _RecoveryTarget target,
    required String idempotencyScope,
    required String credentialField,
    required String forbiddenCredentialField,
    String? recoverySessionId,
  }) async {
    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(userServiceUrl).resolve(accountVerificationExchangePath),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              'provider': 'sms',
              'purpose': purpose,
              'phone': _required(phone, 'phone'),
              'code': _required(otp, 'otp'),
              'target_handle': target.handle,
              'target_handle_domain': target.domain,
              'idempotency_scope': _required(
                idempotencyScope,
                'idempotencyScope',
              ),
              if (recoverySessionId != null)
                'recovery_session_id': recoverySessionId,
            }),
          )
          .timeout(_timeout);
    } on Object {
      throw const HandleRecoveryTransportException(
        'account_verification_network',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HandleRecoveryTransportException(
        'account_verification_http_${response.statusCode}',
      );
    }

    try {
      final payload = jsonDecode(response.body);
      if (payload is! Map ||
          payload['purpose'] != purpose ||
          payload[forbiddenCredentialField] != null) {
        throw const FormatException();
      }
      final token = payload[credentialField]?.toString() ?? '';
      if (token.trim().isEmpty) {
        throw const FormatException();
      }
      return token;
    } on Object {
      throw const HandleRecoveryTransportException(
        'account_verification_invalid_response',
      );
    }
  }

  HandleRecoveryProgress _progressFromCore(core.HandleRecoveryProgress value) {
    final target = _targetFromCanonical(value.handle);
    return HandleRecoveryProgress(
      recoverySessionId: value.recoverySessionId,
      handle: target.handle,
      handleDomain: target.domain,
      oldDid: value.oldDid,
      side: switch (value.side) {
        core.HandleRecoverySide.requester => HandleRecoverySide.requester,
        core.HandleRecoverySide.oldAdmin => HandleRecoverySide.oldAdmin,
      },
      phase: _phaseFromCore(value.phase),
      coolingUntil: _timestamp(value.coolingUntil),
      expiresAt: _timestamp(value.expiresAt),
      canCancelFromThisDevice: value.canCancelFromThisDevice,
      newDid: value.newDid,
      localActivationPending: value.localActivationPending,
    );
  }

  AppSession _activationCandidate(core.IdentitySummary identity) {
    if (!identity.readyForAuth) {
      throw const HandleRecoveryTransportException(
        'invalid_activation_identity',
      );
    }
    return _mappers.appSessionFromIdentity(identity, authenticated: true);
  }

  _RecoveryTarget _target(String handle, String handleDomain) {
    final localPart = _normalizeHandle(handle);
    final domain = _normalizeDomain(handleDomain);
    if (domain != targetHandleDomain) {
      throw const HandleRecoveryTransportException('recovery_domain_mismatch');
    }
    return _RecoveryTarget(handle: localPart, domain: domain);
  }

  _RecoveryTarget _targetFromCanonical(String canonicalHandle) {
    final normalized = canonicalHandle.trim().toLowerCase();
    final suffix = '.$targetHandleDomain';
    if (!normalized.endsWith(suffix)) {
      throw const HandleRecoveryTransportException(
        'invalid_recovery_projection',
      );
    }
    final localPart = normalized.substring(
      0,
      normalized.length - suffix.length,
    );
    return _target(localPart, targetHandleDomain);
  }
}

class HandleRecoveryTransportException implements Exception {
  const HandleRecoveryTransportException(this.code);

  final String code;

  @override
  String toString() => 'HandleRecoveryTransportException($code)';
}

class _RecoveryTarget {
  const _RecoveryTarget({required this.handle, required this.domain});

  final String handle;
  final String domain;

  String get canonicalHandle => '$handle.$domain';
}

HandleRecoveryPhase _phaseFromCore(core.HandleRecoveryPhase value) =>
    switch (value) {
      core.HandleRecoveryPhase.cooling => HandleRecoveryPhase.cooling,
      core.HandleRecoveryPhase.ready => HandleRecoveryPhase.ready,
      core.HandleRecoveryPhase.cancelled => HandleRecoveryPhase.cancelled,
      core.HandleRecoveryPhase.expired => HandleRecoveryPhase.expired,
      core.HandleRecoveryPhase.consumed => HandleRecoveryPhase.consumed,
    };

DateTime _timestamp(String value) {
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const HandleRecoveryTransportException('invalid_recovery_projection');
  }
  return parsed.toUtc();
}

String _required(String value, String field) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw HandleRecoveryTransportException('invalid_$field');
  }
  return normalized;
}

String _normalizeDomain(String value) {
  final normalized = _required(
    value,
    'handleDomain',
  ).replaceAll(RegExp(r'^\.+|\.+$'), '').toLowerCase();
  if (normalized.isEmpty ||
      Uri.tryParse('https://$normalized')?.host != normalized) {
    throw const HandleRecoveryTransportException('invalid_handle_domain');
  }
  return normalized;
}

String _normalizeHandle(String value) {
  final normalized = _required(value, 'handle').toLowerCase();
  if (normalized.length > 63 ||
      normalized.startsWith('-') ||
      normalized.endsWith('-') ||
      normalized.codeUnits.any(
        (unit) =>
            !((unit >= 97 && unit <= 122) ||
                (unit >= 48 && unit <= 57) ||
                unit == 45),
      )) {
    throw const HandleRecoveryTransportException('invalid_handle');
  }
  return normalized;
}

String _newRecoveryIdempotencyScope(String purpose, String? recoverySessionId) {
  final random = Random.secure();
  final bytes = Uint8List(18);
  for (var index = 0; index < bytes.length; index += 1) {
    bytes[index] = random.nextInt(256);
  }
  final kind = purpose == AwikiImCoreHandleRecoveryAdapter.finalizePurpose
      ? 'finalize'
      : 'begin';
  return 'recovery-$kind:${base64UrlEncode(bytes).replaceAll('=', '')}';
}
