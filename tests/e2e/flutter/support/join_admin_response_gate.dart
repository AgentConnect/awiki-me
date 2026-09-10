import 'dart:async';

import 'package:awiki_me/src/application/device_management_service.dart';
import 'package:awiki_me/src/domain/entities/device_management.dart';

/// Delays one real Core response; never manufactures identity or device facts.
class JoinAdminResponseGateService extends DeviceManagementService {
  JoinAdminResponseGateService({
    required super.core,
    required super.userPresence,
  });

  Completer<void>? _releaseVerification;
  bool verificationCaptured = false;
  int registryReadCount = 0;
  Completer<void>? _releaseApproval;
  bool approvalCaptured = false;

  void holdNextVerification() {
    if (_releaseVerification != null) {
      throw StateError('verification_response_already_held');
    }
    verificationCaptured = false;
    _releaseVerification = Completer<void>();
  }

  void releaseVerification() {
    final release = _releaseVerification;
    _releaseVerification = null;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<DeviceJoinProgress> restoreAdminVerificationProgress({
    required String selector,
    required String joinSessionId,
  }) async {
    final response = await super.restoreAdminVerificationProgress(
      selector: selector,
      joinSessionId: joinSessionId,
    );
    final release = _releaseVerification;
    if (release != null && !verificationCaptured) {
      verificationCaptured = true;
      await release.future;
    }
    return response;
  }

  void holdNextApproval() {
    if (_releaseApproval != null) {
      throw StateError('approval_response_already_held');
    }
    approvalCaptured = false;
    _releaseApproval = Completer<void>();
  }

  void releaseApproval() {
    final release = _releaseApproval;
    _releaseApproval = null;
    if (release != null && !release.isCompleted) release.complete();
  }

  @override
  Future<DeviceJoinProgress> approveAsMember({
    required String selector,
    required DeviceJoinProgress progress,
    required String displayedSas,
    required bool sasConfirmed,
    required String presenceReason,
  }) async {
    final response = await super.approveAsMember(
      selector: selector,
      progress: progress,
      displayedSas: displayedSas,
      sasConfirmed: sasConfirmed,
      presenceReason: presenceReason,
    );
    final release = _releaseApproval;
    if (release != null && !approvalCaptured) {
      approvalCaptured = true;
      await release.future;
    }
    return response;
  }

  @override
  Future<DeviceRegistrySnapshot> loadRegistry(String selector) async {
    final result = await super.loadRegistry(selector);
    registryReadCount++;
    return result;
  }
}
