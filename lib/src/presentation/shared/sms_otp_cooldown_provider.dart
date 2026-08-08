// [INPUT]: Purpose-scoped UTC retry boundary, serialized send intent, and wall clock.
// [OUTPUT]: Reactive registration/Join and Recovery resend cooldowns.
// [POS]: Presentation coordinator; OTP values and target validity remain flow-owned.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/sms_otp_cooldown_service.dart';

const _unset = Object();

class SmsOtpCooldownState {
  const SmsOtpCooldownState({
    this.isReady = false,
    this.isSending = false,
    this.retryAt,
    this.remainingSeconds = 0,
  });

  final bool isReady;
  final bool isSending;
  final DateTime? retryAt;
  final int remainingSeconds;

  bool get isCoolingDown => remainingSeconds > 0;
  bool get canSend => isReady && !isSending && !isCoolingDown;

  SmsOtpCooldownState copyWith({
    bool? isReady,
    bool? isSending,
    Object? retryAt = _unset,
    int? remainingSeconds,
  }) {
    return SmsOtpCooldownState(
      isReady: isReady ?? this.isReady,
      isSending: isSending ?? this.isSending,
      retryAt: identical(retryAt, _unset) ? this.retryAt : retryAt as DateTime?,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
    );
  }
}

final smsOtpCooldownClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final smsOtpCooldownProvider =
    StateNotifierProvider<SmsOtpCooldownController, SmsOtpCooldownState>((ref) {
      return SmsOtpCooldownController(
        service: ref.watch(smsOtpCooldownServiceProvider),
        now: ref.watch(smsOtpCooldownClockProvider),
      );
    });

final handleRecoverySmsOtpCooldownProvider =
    StateNotifierProvider<SmsOtpCooldownController, SmsOtpCooldownState>((ref) {
      return SmsOtpCooldownController(
        service: ref.watch(smsOtpCooldownServiceProvider),
        now: ref.watch(smsOtpCooldownClockProvider),
        purpose: SmsOtpCooldownPurpose.handleRecovery,
      );
    });

class SmsOtpCooldownController extends StateNotifier<SmsOtpCooldownState> {
  SmsOtpCooldownController({
    required SmsOtpCooldownService service,
    required DateTime Function() now,
    this.purpose = SmsOtpCooldownPurpose.registrationAndJoin,
  }) : _service = service,
       _now = now,
       super(const SmsOtpCooldownState()) {
    _restoreFuture = _restore();
  }

  static const int maxCooldownSeconds = 3600;

  final SmsOtpCooldownService _service;
  final DateTime Function() _now;
  final SmsOtpCooldownPurpose purpose;
  late final Future<void> _restoreFuture;
  Timer? _timer;
  bool _disposed = false;

  Future<bool> beginSend() async {
    await _restoreFuture;
    if (_disposed || !state.canSend) return false;
    state = state.copyWith(isSending: true);
    return true;
  }

  Future<void> completeAcceptedAt(DateTime retryAt) {
    return _completeWithBoundary(retryAt);
  }

  Future<void> completeAcceptedAfter(int retryAfterSeconds) {
    return _completeWithBoundary(_retryAtAfter(retryAfterSeconds));
  }

  Future<void> completeRateLimitedAt(DateTime retryAt) {
    return _completeWithBoundary(retryAt);
  }

  Future<void> completeRateLimitedAfter(int retryAfterSeconds) {
    return _completeWithBoundary(_retryAtAfter(retryAfterSeconds));
  }

  void completeFailed() {
    if (_disposed || !state.isSending) return;
    state = state.copyWith(isSending: false);
  }

  Future<void> _restore() async {
    DateTime? retryAt;
    try {
      retryAt = await _service.loadRetryAt(purpose: purpose);
    } on Object {
      retryAt = null;
    }
    if (_disposed) return;
    final boundary = _validBoundary(retryAt);
    if (boundary == null) {
      state = const SmsOtpCooldownState(isReady: true);
      if (retryAt != null) unawaited(_clearPersistedBoundary());
      return;
    }
    _applyBoundary(boundary, isSending: false);
  }

  Future<void> _completeWithBoundary(DateTime retryAt) async {
    if (_disposed) return;
    final boundary = _validBoundary(retryAt);
    if (boundary == null) {
      state = state.copyWith(isSending: false);
      return;
    }
    final current = _validBoundary(state.retryAt);
    final effective = current != null && current.isAfter(boundary)
        ? current
        : boundary;
    _applyBoundary(effective, isSending: false);
    try {
      await _service.saveRetryAt(effective, purpose: purpose);
    } on Object {
      // Keep the process-local boundary even when best-effort persistence fails.
    }
  }

  void _applyBoundary(DateTime retryAt, {required bool isSending}) {
    _timer?.cancel();
    final remaining = _secondsRemaining(retryAt);
    state = SmsOtpCooldownState(
      isReady: true,
      isSending: isSending,
      retryAt: retryAt,
      remainingSeconds: remaining,
    );
    if (remaining == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      final next = _secondsRemaining(retryAt);
      if (next == 0) {
        timer.cancel();
        state = SmsOtpCooldownState(isReady: true, isSending: state.isSending);
        unawaited(_clearPersistedBoundary());
        return;
      }
      state = state.copyWith(remainingSeconds: next);
    });
  }

  DateTime _retryAtAfter(int seconds) {
    final bounded = seconds.clamp(1, maxCooldownSeconds).toInt();
    return _now().toUtc().add(Duration(seconds: bounded));
  }

  DateTime? _validBoundary(DateTime? value) {
    if (value == null) return null;
    final boundary = value.toUtc();
    final now = _now().toUtc();
    if (!boundary.isAfter(now)) return null;
    if (boundary.isAfter(
      now.add(const Duration(seconds: maxCooldownSeconds)),
    )) {
      return null;
    }
    return boundary;
  }

  int _secondsRemaining(DateTime retryAt) {
    final milliseconds = retryAt.difference(_now().toUtc()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return ((milliseconds + 999) ~/ 1000).clamp(1, maxCooldownSeconds).toInt();
  }

  Future<void> _clearPersistedBoundary() async {
    try {
      await _service.clearRetryAt(purpose: purpose);
    } on Object {
      // Expired/corrupt state cannot block sending even when cleanup fails.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
