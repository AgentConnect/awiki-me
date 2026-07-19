import '../../domain/entities/handle_recovery.dart';
import '../models/app_session.dart';
import '../models/handle_recovery_completion.dart';

/// AWiki-internal Handle Recovery boundary owned by AWiki Me.
///
/// OTP values are write-only inputs. The adapter must exchange them for the
/// exact `awiki.device.recovery.begin.v1` or
/// `awiki.device.recovery.finalize.v1` grant and immediately hand that grant to
/// Core. Both exchanges bind the exact Handle/domain; finalize additionally
/// binds the Recovery Session. Recovery/session tokens, private keys, DID
/// documents, and key material must never be projected through this port.
abstract interface class HandleRecoveryPort {
  Future<void> sendRecoveryBeginSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
  });

  Future<void> sendRecoveryFinalizeSmsOtp({
    required String phone,
    required String handle,
    required String handleDomain,
    required String recoverySessionId,
  });

  Future<List<HandleRecoveryProgress>> localHandleRecoverySessions();

  Future<HandleRecoveryProgress> beginHandleRecoveryWithSms({
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  });

  Future<HandleRecoveryProgress> pollHandleRecovery(String recoverySessionId);

  Future<HandleRecoveryProgress> cancelHandleRecovery({
    required String selector,
    required String recoverySessionId,
  });

  Future<HandleRecoveryCompletion> finalizeHandleRecoveryWithSms({
    required String recoverySessionId,
    required String handle,
    required String handleDomain,
    required String phone,
    required String otp,
  });

  /// Reloads the authenticated identity that Core persisted before cutover.
  /// The returned session must be handed directly to AppRuntime and must not be
  /// retained in Riverpod state or logs.
  Future<AppSession> resumeRecoveryActivation(String recoverySessionId);

  /// Clears Core's durable local-activation-pending marker after AppRuntime and
  /// E2EE initialization both complete.
  Future<void> markRecoveryActivationComplete(String recoverySessionId);
}
