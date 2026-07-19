import 'dart:convert';

import 'package:awiki_im_core/awiki_im_core.dart' as core;
import 'package:http/http.dart' as http;

import '../../application/ports/device_management_core_port.dart';
import '../../domain/entities/device_management.dart';
import 'awiki_im_core_runtime.dart';

typedef AwikiImCoreBeginDeviceJoin =
    Future<core.DeviceJoinProgress> Function({
      required String did,
      required String operationId,
      required int ttlSeconds,
      required core.DeviceJoinAccountVerificationGrant accountVerificationGrant,
    });

typedef AwikiImCoreInstance = Future<core.AwikiImCore> Function();

/// AWiki-internal account verification plus the secret-free IM Core Join API.
///
/// The account-verification token exists only as a method-local value. It is
/// wrapped in Core's single-use grant and consumed immediately; it is never
/// returned to application or presentation state.
class AwikiImCoreDeviceManagementAdapter implements DeviceManagementCorePort {
  AwikiImCoreDeviceManagementAdapter({
    required AwikiImCoreRuntime runtime,
    required String userServiceUrl,
    required String targetHandleDomain,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
    AwikiImCoreBeginDeviceJoin? beginDeviceJoin,
  }) : this.withCoreInstance(
         coreInstance: runtime.coreInstance,
         userServiceUrl: userServiceUrl,
         targetHandleDomain: targetHandleDomain,
         httpClient: httpClient,
         timeout: timeout,
         beginDeviceJoin: beginDeviceJoin,
       );

  AwikiImCoreDeviceManagementAdapter.withCoreInstance({
    required AwikiImCoreInstance coreInstance,
    required this.userServiceUrl,
    required this.targetHandleDomain,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 20),
    AwikiImCoreBeginDeviceJoin? beginDeviceJoin,
  }) : _coreInstance = coreInstance,
       _httpClient = httpClient ?? http.Client(),
       _timeout = timeout,
       _beginDeviceJoin =
           beginDeviceJoin ??
           (({
             required did,
             required operationId,
             required ttlSeconds,
             required accountVerificationGrant,
           }) async {
             final instance = await coreInstance();
             return instance.beginDeviceJoin(
               did: did,
               operationId: operationId,
               ttlSeconds: ttlSeconds,
               accountVerificationGrant: accountVerificationGrant,
             );
           });

  static const String accountVerificationExchangePath =
      '/user-service/auth/account-verification/exchange';
  static const String smsCodePath = '/user-service/auth/sms-codes';

  final AwikiImCoreInstance _coreInstance;
  final String userServiceUrl;
  final String targetHandleDomain;
  final http.Client _httpClient;
  final Duration _timeout;
  final AwikiImCoreBeginDeviceJoin _beginDeviceJoin;

  @override
  Future<void> sendJoinSmsOtp(String phone) async {
    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(userServiceUrl).resolve(smsCodePath),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{'phone': phone.trim()}),
          )
          .timeout(_timeout);
    } on Object {
      throw const DeviceManagementTransportException('sms_code_network');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeviceManagementTransportException(
        'sms_code_http_${response.statusCode}',
      );
    }
  }

  @override
  Future<List<DeviceJoinProgress>> localDeviceJoinSessions() async {
    final instance = await _coreInstance();
    final sessions = await instance.localDeviceJoinSessions();
    return sessions.map(deviceJoinSessionFromCore).toList(growable: false);
  }

  @override
  Future<DeviceJoinProgress> beginDeviceJoinWithSms({
    required String did,
    required String handle,
    required String phone,
    required String otp,
    required String operationId,
    required int ttlSeconds,
  }) async {
    final handleTarget = _handleTarget(handle, targetHandleDomain);
    final token = await _exchangeSmsOtp(
      phone: phone,
      otp: otp,
      targetHandle: handleTarget.handle,
      targetDomain: handleTarget.domain,
      operationId: operationId,
    );
    final grant = core.DeviceJoinAccountVerificationGrant.fromToken(token);
    final result = await _beginDeviceJoin(
      did: did,
      operationId: operationId,
      ttlSeconds: ttlSeconds,
      accountVerificationGrant: grant,
    );
    return deviceJoinProgressFromCore(result);
  }

  @override
  Future<DeviceJoinProgress> pollNewDeviceJoin(String joinSessionId) async {
    final instance = await _coreInstance();
    return deviceJoinProgressFromCore(
      await instance.pollNewDeviceJoin(joinSessionId),
    );
  }

  @override
  Future<DeviceJoinProgress> cancelNewDeviceJoin(String joinSessionId) async {
    final instance = await _coreInstance();
    return deviceJoinSessionFromCore(
      await instance.cancelNewDeviceJoin(joinSessionId),
    );
  }

  @override
  Future<DeviceRegistrySnapshot> identityDeviceRegistry(String selector) async {
    final instance = await _coreInstance();
    final result = await instance.identityDeviceRegistry(
      _identitySelector(selector),
    );
    return deviceRegistryFromCore(result);
  }

  @override
  Future<DeviceJoinProgress> claimDeviceJoin({
    required String selector,
    required String joinSessionId,
    required String operationId,
    required int challengeTtlSeconds,
  }) async {
    final instance = await _coreInstance();
    final result = await instance.claimDeviceJoin(
      selector: _identitySelector(selector),
      joinSessionId: joinSessionId,
      operationId: operationId,
      challengeTtlSeconds: challengeTtlSeconds,
    );
    return deviceJoinProgressFromCore(result);
  }

  @override
  Future<DeviceJoinProgress> pollAdminDeviceJoin({
    required String selector,
    required String joinSessionId,
  }) async {
    final instance = await _coreInstance();
    final result = await instance.pollAdminDeviceJoin(
      selector: _identitySelector(selector),
      joinSessionId: joinSessionId,
    );
    return deviceJoinProgressFromCore(result);
  }

  @override
  Future<DeviceJoinApprovalPrompt> prepareDeviceJoinApproval({
    required String selector,
    required String joinSessionId,
    required DeviceRole role,
    required bool sasConfirmed,
  }) async {
    final instance = await _coreInstance();
    final result = await instance.prepareDeviceJoinApproval(
      selector: _identitySelector(selector),
      joinSessionId: joinSessionId,
      role: _roleToCore(role),
      sasConfirmed: sasConfirmed,
    );
    return DeviceJoinApprovalPrompt(
      approvalHandle: result.approvalHandle,
      joinSessionId: result.joinSessionId,
      role: _roleFromCore(result.role),
      sas: result.sas,
      expiresAt: _timestamp(result.expiresAt),
    );
  }

  @override
  Future<DeviceJoinProgress> confirmDeviceJoinApproval({
    required String approvalHandle,
    required bool userPresenceConfirmed,
  }) async {
    final instance = await _coreInstance();
    final result = await instance.confirmDeviceJoinApproval(
      approvalHandle: approvalHandle,
      userPresenceConfirmed: userPresenceConfirmed,
    );
    return deviceJoinProgressFromCore(result);
  }

  @override
  Future<DeviceJoinProgress> cancelAdminDeviceJoin({
    required String selector,
    required String joinSessionId,
  }) async {
    final instance = await _coreInstance();
    return deviceJoinSessionFromCore(
      await instance.cancelAdminDeviceJoin(
        selector: _identitySelector(selector),
        joinSessionId: joinSessionId,
      ),
    );
  }

  Future<String> _exchangeSmsOtp({
    required String phone,
    required String otp,
    required String targetHandle,
    required String targetDomain,
    required String operationId,
  }) async {
    http.Response response;
    try {
      response = await _httpClient
          .post(
            Uri.parse(userServiceUrl).resolve(accountVerificationExchangePath),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, Object?>{
              'provider': 'sms',
              'purpose': 'awiki.device.join.v1',
              'phone': phone.trim(),
              'code': otp,
              'target_handle': targetHandle,
              'target_handle_domain': targetDomain,
              'idempotency_scope': operationId,
            }),
          )
          .timeout(_timeout);
    } on Object {
      throw const DeviceManagementTransportException(
        'account_verification_network',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeviceManagementTransportException(
        'account_verification_http_${response.statusCode}',
      );
    }

    try {
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['purpose'] != 'awiki.device.join.v1') {
        throw const FormatException();
      }
      final token = payload['account_verification_token']?.toString() ?? '';
      if (token.trim().isEmpty) {
        throw const FormatException();
      }
      return token;
    } on Object {
      throw const DeviceManagementTransportException(
        'account_verification_invalid_response',
      );
    }
  }
}

class DeviceManagementTransportException implements Exception {
  const DeviceManagementTransportException(this.code);

  final String code;

  @override
  String toString() => 'DeviceManagementTransportException($code)';
}

DeviceJoinProgress deviceJoinSessionFromCore(
  core.DeviceJoinSessionSummary session,
) {
  return DeviceJoinProgress(
    joinSessionId: session.joinSessionId,
    did: session.did,
    protocolDeviceId: session.protocolDeviceId,
    side: _sideFromCore(session.side),
    phase: _phaseFromCore(session.phase),
    remoteState: DeviceJoinRemoteState.notObserved,
    expiresAt: _timestamp(session.expiresAt),
  );
}

DeviceJoinProgress deviceJoinProgressFromCore(core.DeviceJoinProgress value) {
  final session = value.session;
  return DeviceJoinProgress(
    joinSessionId: session.joinSessionId,
    did: session.did,
    protocolDeviceId: session.protocolDeviceId,
    side: _sideFromCore(session.side),
    phase: _phaseFromCore(session.phase),
    remoteState: _remoteStateFromCore(value.remoteState),
    expiresAt: _timestamp(session.expiresAt),
    sas: value.sas,
    authorizedDevice: value.authorizedDevice == null
        ? null
        : _deviceFromCore(value.authorizedDevice!),
  );
}

DeviceRegistrySnapshot deviceRegistryFromCore(
  core.DeviceJoinRegistrySnapshot value,
) {
  return DeviceRegistrySnapshot(
    did: value.did,
    devices: value.devices.map(_deviceFromCore).toList(growable: false),
    pendingJoins: value.pendingJoinRequests
        .map(
          (pending) => PendingDeviceJoinSummary(
            joinSessionId: pending.joinSessionId,
            protocolDeviceId: pending.protocolDeviceId,
            signingKeyId: pending.signingKeyId,
            e2eeKeyId: pending.e2eeKeyId,
            requestedRole: _roleFromCore(pending.requestedRole),
            issuedAt: _timestamp(pending.issuedAt),
            expiresAt: _timestamp(pending.expiresAt),
          ),
        )
        .toList(growable: false),
  );
}

DeviceSummary _deviceFromCore(core.DeviceJoinAuthorizedDeviceSummary value) {
  return DeviceSummary(
    protocolDeviceId: value.protocolDeviceId,
    signingKeyId: value.signingKeyId,
    e2eeKeyId: value.e2eeKeyId,
    status: switch (value.status) {
      core.DeviceJoinAuthorizationStatus.active => DeviceStatus.active,
      core.DeviceJoinAuthorizationStatus.revoked => DeviceStatus.revoked,
    },
    role: _roleFromCore(value.role),
    managementReady: value.managementReady,
    isCurrent: value.isCurrent,
  );
}

DeviceJoinSide _sideFromCore(core.DeviceJoinSide value) => switch (value) {
  core.DeviceJoinSide.newDevice => DeviceJoinSide.newDevice,
  core.DeviceJoinSide.admin => DeviceJoinSide.admin,
};

DeviceJoinPhase _phaseFromCore(core.DeviceJoinPhase value) => switch (value) {
  core.DeviceJoinPhase.pending => DeviceJoinPhase.pending,
  core.DeviceJoinPhase.challengePrepared => DeviceJoinPhase.challengePrepared,
  core.DeviceJoinPhase.responsePrepared => DeviceJoinPhase.responsePrepared,
  core.DeviceJoinPhase.responseVerified => DeviceJoinPhase.responseVerified,
  core.DeviceJoinPhase.approvalPrepared => DeviceJoinPhase.approvalPrepared,
  core.DeviceJoinPhase.authorized => DeviceJoinPhase.authorized,
  core.DeviceJoinPhase.cancelled => DeviceJoinPhase.cancelled,
  core.DeviceJoinPhase.expired => DeviceJoinPhase.expired,
};

DeviceJoinRemoteState _remoteStateFromCore(core.DeviceJoinRemoteState value) =>
    switch (value) {
      core.DeviceJoinRemoteState.pending => DeviceJoinRemoteState.pending,
      core.DeviceJoinRemoteState.claimed => DeviceJoinRemoteState.claimed,
      core.DeviceJoinRemoteState.challengeSent =>
        DeviceJoinRemoteState.challengeSent,
      core.DeviceJoinRemoteState.responseVerified =>
        DeviceJoinRemoteState.responseVerified,
      core.DeviceJoinRemoteState.consumed => DeviceJoinRemoteState.consumed,
      core.DeviceJoinRemoteState.expired => DeviceJoinRemoteState.expired,
    };

DeviceRole _roleFromCore(core.DeviceJoinRole value) => switch (value) {
  core.DeviceJoinRole.member => DeviceRole.member,
  core.DeviceJoinRole.admin => DeviceRole.admin,
};

core.DeviceJoinRole _roleToCore(DeviceRole value) => switch (value) {
  DeviceRole.member => core.DeviceJoinRole.member,
  DeviceRole.admin => core.DeviceJoinRole.admin,
};

DateTime _timestamp(String value) {
  try {
    return DateTime.parse(value);
  } on FormatException {
    throw const DeviceManagementTransportException(
      'invalid_device_join_timestamp',
    );
  }
}

core.IdentitySelector _identitySelector(String value) {
  final selector = value.trim();
  if (selector.isEmpty) {
    throw const DeviceManagementTransportException('invalid_identity_selector');
  }
  if (selector == 'default') {
    return const core.IdentitySelector.defaultIdentity();
  }
  if (selector.startsWith('did:')) {
    return core.IdentitySelector.did(selector);
  }
  if (selector.startsWith('@')) {
    return core.IdentitySelector.localAlias(selector.substring(1));
  }
  if (selector.contains('.')) {
    return core.IdentitySelector.handle(selector);
  }
  return core.IdentitySelector.id(selector);
}

({String handle, String domain}) _handleTarget(
  String value,
  String fallbackDomain,
) {
  final normalized = value.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
  final domain = fallbackDomain.trim().toLowerCase();
  if (normalized.isEmpty || domain.isEmpty) {
    throw const DeviceManagementTransportException('invalid_handle_target');
  }
  final separator = normalized.indexOf('.');
  if (separator < 0) {
    return (handle: normalized, domain: domain);
  }
  final handle = normalized.substring(0, separator);
  final qualifiedDomain = normalized.substring(separator + 1);
  if (handle.isEmpty || qualifiedDomain.isEmpty) {
    throw const DeviceManagementTransportException('invalid_handle_target');
  }
  return (handle: handle, domain: qualifiedDomain);
}
