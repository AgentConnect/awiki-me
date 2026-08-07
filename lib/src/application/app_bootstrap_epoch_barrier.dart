// [INPUT]: Core-selected identity/binding, Core-authorized epoch receipt, Product epoch.
// [OUTPUT]: A fail-closed readiness decision before App session activation.
// [POS]: Single App bootstrap fence; Core owns crypto/control transition, App owns Product reset.

import 'dart:developer' as developer;

import '../domain/entities/handle_recovery.dart';
import '../domain/entities/session_identity.dart';
import 'models/app_session.dart';
import 'models/product_local_models.dart';
import 'ports/handle_recovery_core_port.dart';
import 'product_local_store.dart';

abstract interface class AppBootstrapEpochBarrierPort {
  Future<void> ensureReady({
    required AppSession identity,
    required SessionAccountBinding binding,
  });
}

/// Used only by composition roots/tests that do not have Product account state.
/// Production bootstrap must inject [AppBootstrapEpochBarrier].
class NoopAppBootstrapEpochBarrier implements AppBootstrapEpochBarrierPort {
  const NoopAppBootstrapEpochBarrier();

  @override
  Future<void> ensureReady({
    required AppSession identity,
    required SessionAccountBinding binding,
  }) async {}
}

enum AppBootstrapEpochBarrierFailureCode {
  missingStableOwner,
  unknownEpoch,
  receiptMismatch,
  resetDidNotConverge,
}

class AppBootstrapEpochBarrierFailure implements Exception {
  const AppBootstrapEpochBarrierFailure(this.code);

  final AppBootstrapEpochBarrierFailureCode code;

  @override
  String toString() => 'AppBootstrapEpochBarrierFailure(${code.name})';
}

class AppBootstrapEpochBarrierMetrics {
  AppBootstrapEpochBarrierMetrics({
    void Function(String metric, String result, int total)? sink,
  }) : _sink = sink ?? _defaultSink;

  final void Function(String metric, String result, int total) _sink;
  final Map<String, int> _counts = <String, int>{};

  void record(String result) {
    final bounded = _barrierMetricResults.contains(result) ? result : 'other';
    final total = (_counts[bounded] ?? 0) + 1;
    _counts[bounded] = total;
    _sink('app_epoch_barrier_total', bounded, total);
  }

  Map<String, int> snapshot() => Map<String, int>.unmodifiable(_counts);

  static void _defaultSink(String metric, String result, int total) {
    developer.log('$metric result=$result total=$total', name: 'awiki.metrics');
  }
}

final AppBootstrapEpochBarrierMetrics appBootstrapEpochBarrierMetrics =
    AppBootstrapEpochBarrierMetrics();

const Set<String> _barrierMetricResults = <String>{
  'ready',
  'cached_ready',
  'coalesced',
  'missing_stable_owner',
  'unknown_epoch',
  'receipt_mismatch',
  'reset_did_not_converge',
  'error',
};

class AppBootstrapEpochBarrier implements AppBootstrapEpochBarrierPort {
  AppBootstrapEpochBarrier({
    required HandleRecoveryCorePort recovery,
    required ProductLocalStore local,
    AppBootstrapEpochBarrierMetrics? metrics,
  }) : _recovery = recovery,
       _local = local,
       _metrics = metrics ?? appBootstrapEpochBarrierMetrics;

  final HandleRecoveryCorePort _recovery;
  final ProductLocalStore _local;
  final AppBootstrapEpochBarrierMetrics _metrics;

  String? _readyKey;
  String? _inFlightKey;
  Future<void>? _inFlight;

  @override
  Future<void> ensureReady({
    required AppSession identity,
    required SessionAccountBinding binding,
  }) {
    final key = _key(identity.identityId, binding);
    if (_readyKey == key) {
      _metrics.record('cached_ready');
      return Future<void>.value();
    }
    if (_inFlightKey == key && _inFlight != null) {
      _metrics.record('coalesced');
      return _inFlight!;
    }
    final rawOperation = _ensureReady(identity: identity, binding: binding);
    final operation = rawOperation.then<void>(
      (_) => _metrics.record('ready'),
      onError: (Object error, StackTrace stackTrace) {
        _metrics.record(_metricResult(error));
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
    _inFlightKey = key;
    _inFlight = operation;
    return operation.whenComplete(() {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
        _inFlightKey = null;
      }
    });
  }

  Future<void> _ensureReady({
    required AppSession identity,
    required SessionAccountBinding binding,
  }) async {
    if (identity.identityId != binding.ownerIdentityId) {
      throw const AppBootstrapEpochBarrierFailure(
        AppBootstrapEpochBarrierFailureCode.missingStableOwner,
      );
    }
    final productBinding = ProductAccountBinding(
      ownerIdentityId: binding.ownerIdentityId,
      accountId: binding.accountId,
    );
    final expectedEpoch = ProductDeviceRegistryEpoch(
      currentDid: binding.currentDid,
      bindingGeneration: binding.identityGeneration,
    );
    final persisted = await _local.loadDeviceRegistryEpoch(
      binding: productBinding,
    );
    if (persisted?.matches(expectedEpoch) ?? false) {
      _readyKey = _key(identity.identityId, binding);
      return;
    }

    var receiptRequired = persisted != null;
    if (persisted == null) {
      final snapshot = await _local.loadDeviceRegistrySnapshot(
        binding: productBinding,
      );
      receiptRequired = snapshot != null;
    }

    final handle = identity.handle?.trim().toLowerCase();
    if (handle == null || handle.isEmpty) {
      if (!receiptRequired) {
        _readyKey = _key(identity.identityId, binding);
        return;
      }
      throw const AppBootstrapEpochBarrierFailure(
        AppBootstrapEpochBarrierFailureCode.missingStableOwner,
      );
    }
    final receipt = await _recovery.authorizedEpochReceipt(
      HandleRecoveryOwner(localIdentityId: identity.identityId, handle: handle),
    );
    if (receipt == null) {
      if (!receiptRequired) {
        _readyKey = _key(identity.identityId, binding);
        return;
      }
      throw const AppBootstrapEpochBarrierFailure(
        AppBootstrapEpochBarrierFailureCode.unknownEpoch,
      );
    }
    _validateReceipt(receipt, identity: identity, binding: binding);
    await _local.applyDeviceRegistryEpochReset(
      ProductDeviceRegistryEpochResetAuthorization(
        reference: ProductDeviceRegistryEpochResetReference(
          accountUserId: receipt.accountUserId,
          ownerIdentityId: receipt.ownerIdentityId,
          previousDid: receipt.previousDid,
          currentDid: receipt.currentDid,
          bindingGeneration: receipt.bindingGeneration,
        ),
        handle: receipt.handle,
        sourceKind:
            receipt.sourceKind == HandleRecoveryTransitionSourceKind.initiator
            ? ProductIdentityTransitionSourceKind.initiator
            : ProductIdentityTransitionSourceKind.joinedDevice,
        sourceId: receipt.sourceId,
      ),
    );
    final applied = await _local.loadDeviceRegistryEpoch(
      binding: productBinding,
    );
    if (!(applied?.matches(expectedEpoch) ?? false)) {
      throw const AppBootstrapEpochBarrierFailure(
        AppBootstrapEpochBarrierFailureCode.resetDidNotConverge,
      );
    }
    _readyKey = _key(identity.identityId, binding);
  }
}

String _metricResult(Object error) {
  if (error is! AppBootstrapEpochBarrierFailure) return 'error';
  return switch (error.code) {
    AppBootstrapEpochBarrierFailureCode.missingStableOwner =>
      'missing_stable_owner',
    AppBootstrapEpochBarrierFailureCode.unknownEpoch => 'unknown_epoch',
    AppBootstrapEpochBarrierFailureCode.receiptMismatch => 'receipt_mismatch',
    AppBootstrapEpochBarrierFailureCode.resetDidNotConverge =>
      'reset_did_not_converge',
  };
}

void _validateReceipt(
  HandleRecoveryRegistryEpochReset receipt, {
  required AppSession identity,
  required SessionAccountBinding binding,
}) {
  final handle = identity.handle?.trim().toLowerCase();
  if (receipt.receiptSchemaVersion != '1' ||
      receipt.accountUserId != binding.accountId ||
      receipt.ownerIdentityId != binding.ownerIdentityId ||
      receipt.ownerIdentityId != identity.identityId ||
      receipt.handle != handle ||
      receipt.currentDid != binding.currentDid ||
      receipt.bindingGeneration != binding.identityGeneration ||
      !_isPositiveDecimal(receipt.bindingGeneration) ||
      receipt.currentDeviceId != binding.protocolDeviceId ||
      receipt.deviceAuthGeneration.toString() != binding.deviceAuthGeneration ||
      receipt.previousDid == receipt.currentDid ||
      !_isPositiveVersion(receipt.deviceAuthGeneration) ||
      !_isPositiveVersion(receipt.registryVersion) ||
      !_isSha256Fingerprint(receipt.stateRootFingerprint) ||
      !receipt.appliedAt.isUtc ||
      receipt.appliedAt.millisecond != 0 ||
      receipt.appliedAt.microsecond != 0 ||
      receipt.metadataJson != '{}' ||
      receipt.sourceId.trim() != receipt.sourceId ||
      receipt.sourceId.isEmpty) {
    throw const AppBootstrapEpochBarrierFailure(
      AppBootstrapEpochBarrierFailureCode.receiptMismatch,
    );
  }
}

bool _isPositiveVersion(int value) => value > 0;

bool _isPositiveDecimal(String value) =>
    value.length <= 255 && RegExp(r'^[1-9][0-9]*$').hasMatch(value);

bool _isSha256Fingerprint(String value) =>
    RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(value);

String _key(String identityId, SessionAccountBinding binding) => <String>[
  identityId,
  binding.ownerIdentityId,
  binding.accountId,
  binding.currentDid,
  binding.identityGeneration,
  binding.protocolDeviceId,
  binding.deviceAuthGeneration,
].join('\u001f');
