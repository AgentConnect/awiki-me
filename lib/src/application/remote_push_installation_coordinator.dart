import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/services/remote_push_client.dart';
import 'ports/push_installation_port.dart';
import 'tenant/app_tenant.dart';

final class RemotePushInstallationSession {
  const RemotePushInstallationSession({
    required this.storageScopeId,
    required this.ownerDid,
    required this.generation,
    this.logicalDeviceId,
  });

  final StorageScopeId storageScopeId;
  final String ownerDid;
  final int generation;
  final String? logicalDeviceId;
}

class RemotePushInstallationCoordinator {
  RemotePushInstallationCoordinator({
    required RemotePushClient client,
    required PushInstallationPort installations,
  }) : _client = client,
       _installations = installations;

  final RemotePushClient _client;
  final PushInstallationPort _installations;

  Future<void> _mutationTail = Future<void>.value();
  RemotePushInstallationSession? _desiredSession;
  _BoundInstallation? _boundInstallation;
  int _desiredRevision = 0;

  Future<void> bindActiveSession(RemotePushInstallationSession session) {
    final revision = _setDesiredSession(session);
    return _serialize(
      () => _bind(session, revision: revision, initializeWhenNeeded: true),
    );
  }

  Future<void> refreshActiveSession(RemotePushInstallationSession session) {
    if (!_sameSessionIdentity(_desiredSession, session)) {
      return _serialize(() async {});
    }
    final revision = _setDesiredSession(session);
    return _serialize(() async {
      if (!_isDesired(session, revision)) {
        return;
      }
      await _bind(session, revision: revision, initializeWhenNeeded: false);
    });
  }

  Future<void> disableActiveInstallation(
    RemotePushInstallationSession session,
  ) {
    deactivateLocally(session);
    return _serialize(() => _disableBoundInstallation(expected: session));
  }

  Future<void> disableCurrentInstallation() {
    _clearDesiredSession();
    return _serialize(() => _disableBoundInstallation());
  }

  void deactivateLocally(RemotePushInstallationSession session) {
    if (!_sameSessionIdentity(_desiredSession, session)) {
      return;
    }
    _clearDesiredSession();
  }

  int _setDesiredSession(RemotePushInstallationSession session) {
    if (_sameSessionSnapshot(_desiredSession, session)) {
      return _desiredRevision;
    }
    _desiredSession = session;
    _desiredRevision += 1;
    final bound = _boundInstallation;
    if (bound != null) {
      bound.markUnaccepted();
    }
    return _desiredRevision;
  }

  void _clearDesiredSession() {
    if (_desiredSession == null) {
      return;
    }
    _desiredSession = null;
    _desiredRevision += 1;
    final bound = _boundInstallation;
    if (bound != null) {
      bound.markUnaccepted();
    }
  }

  Future<void> _bind(
    RemotePushInstallationSession session, {
    required int revision,
    required bool initializeWhenNeeded,
  }) async {
    if (!_isDesired(session, revision)) {
      return;
    }

    final existing = _boundInstallation;
    if (existing != null &&
        (!_sameSessionIdentity(existing.session, session) ||
            !existing.accepted)) {
      final replacesAnotherSession = !_sameSessionIdentity(
        existing.session,
        session,
      );
      try {
        await _disableBoundInstallation();
      } catch (_) {
        if (!replacesAnotherSession) {
          rethrow;
        }
        if (identical(_boundInstallation, existing)) {
          _boundInstallation = null;
        }
      }
      if (!_isDesired(session, revision)) {
        return;
      }
    }

    final rawRegistration = initializeWhenNeeded
        ? await _registrationForBind()
        : await _registrationForRefresh();
    if (rawRegistration == null || !_isDesired(session, revision)) {
      return;
    }

    final registration = rawRegistration.withLogicalDeviceId(
      session.logicalDeviceId,
    );
    final fingerprint = _registrationFingerprint(registration);
    final current = _boundInstallation;
    if (current != null &&
        current.accepted &&
        _sameSessionIdentity(current.session, session) &&
        current.registrationFingerprint == fingerprint) {
      return;
    }

    if (current != null) {
      await _disableBoundInstallation();
      if (!_isDesired(session, revision)) {
        return;
      }
    }

    final installation = await _installations.upsert(registration);
    _boundInstallation = _BoundInstallation(
      session: session,
      installationId: installation.installationId,
      registrationFingerprint: fingerprint,
      accepted: _isDesired(session, revision),
    );
  }

  Future<RemotePushRegistration?> _registrationForBind() {
    final current = _boundInstallation;
    if (current != null && current.accepted) {
      final registration = _client.registration;
      if (registration != null) {
        return Future<RemotePushRegistration?>.value(registration);
      }
    }
    return _client.initialize();
  }

  Future<RemotePushRegistration?> _registrationForRefresh() async {
    return _client.registration ?? await _client.initialize();
  }

  Future<void> _disableBoundInstallation({
    RemotePushInstallationSession? expected,
  }) async {
    final current = _boundInstallation;
    if (current == null ||
        (expected != null &&
            !_sameSessionIdentity(current.session, expected))) {
      return;
    }
    await _installations.disable(current.installationId);
    if (identical(_boundInstallation, current)) {
      _boundInstallation = null;
    }
  }

  bool _isDesired(RemotePushInstallationSession session, int revision) {
    return revision == _desiredRevision &&
        _sameSessionSnapshot(_desiredSession, session);
  }

  Future<void> _serialize(Future<void> Function() mutation) {
    final operation = _mutationTail.then((_) => mutation());
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }
}

final class _BoundInstallation {
  _BoundInstallation({
    required this.session,
    required this.installationId,
    required this.registrationFingerprint,
    required this.accepted,
  });

  final RemotePushInstallationSession session;
  final String installationId;
  final String registrationFingerprint;
  bool accepted;

  void markUnaccepted() => accepted = false;
}

bool _sameSessionIdentity(
  RemotePushInstallationSession? left,
  RemotePushInstallationSession? right,
) {
  return left != null &&
      right != null &&
      left.storageScopeId == right.storageScopeId &&
      left.ownerDid == right.ownerDid &&
      left.generation == right.generation;
}

bool _sameSessionSnapshot(
  RemotePushInstallationSession? left,
  RemotePushInstallationSession? right,
) {
  return _sameSessionIdentity(left, right) &&
      left!.logicalDeviceId == right!.logicalDeviceId;
}

String _registrationFingerprint(RemotePushRegistration registration) {
  final fields = <String>[
    registration.provider,
    registration.providerDeviceId,
    registration.platform,
    registration.clientProduct,
    registration.clientVersion,
    ...registration.capabilities,
    registration.appId ?? '',
    registration.logicalDeviceId ?? '',
  ];
  final encoded = fields.map((value) => '${value.length}:$value').join('|');
  return sha256.convert(utf8.encode(encoded)).toString();
}
