import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../application/onboarding_support_service.dart';
import '../../application/tenant/app_tenant.dart';

enum RegistrationEntryStep { account, invite, verification }

class RegistrationEntryState {
  const RegistrationEntryState({
    this.step = RegistrationEntryStep.account,
    this.check,
    this.handle = '',
    this.domain = '',
    this.inviteCode = '',
    this.busy = false,
    this.error,
    this.existingAccountPath = false,
  });

  final RegistrationEntryStep step;
  final RegistrationCheck? check;
  final String handle;
  final String domain;
  final String inviteCode;
  final bool busy;
  final String? error;
  final bool existingAccountPath;
}

/// Owns only transient form state; server/Core retain all identity authority.
class RegistrationEntryController
    extends StateNotifier<RegistrationEntryState> {
  RegistrationEntryController(this.support)
    : super(const RegistrationEntryState());
  final OnboardingSupportService support;
  int _revision = 0;

  void reset() {
    _revision++;
    state = const RegistrationEntryState();
  }

  void invalidateVerification() {
    _revision++;
    state = _state(busy: false);
  }

  RegistrationEntryState _state({
    RegistrationEntryStep? step,
    RegistrationCheck? check,
    String? inviteCode,
    bool busy = false,
    String? error,
  }) => RegistrationEntryState(
    step: step ?? state.step,
    check: check ?? state.check,
    handle: state.handle,
    domain: state.domain,
    inviteCode: inviteCode ?? state.inviteCode,
    busy: busy,
    error: error,
    existingAccountPath: state.existingAccountPath,
  );

  Future<void> checkAccount(String handle, String domain) async {
    if (state.busy) return;
    final revision = ++_revision;
    state = RegistrationEntryState(
      handle: handle.trim().toLowerCase(),
      domain: domain.trim().toLowerCase(),
      busy: true,
    );
    try {
      final result = await support
          .checkRegistration(handle: state.handle, domain: state.domain)
          .timeout(const Duration(seconds: 20));
      if (!mounted || revision != _revision) return;
      state = _state(
        check: result,
        step: result.decision == 'unavailable'
            ? RegistrationEntryStep.account
            : result.inviteRequired
            ? RegistrationEntryStep.invite
            : RegistrationEntryStep.verification,
        error: result.decision == 'unavailable'
            ? result.reason ?? 'handle_unavailable'
            : null,
      );
    } catch (_) {
      if (mounted && revision == _revision) {
        state = _state(error: 'check_failed');
      }
    }
  }

  Future<void> continueWithInvite(String code) async {
    if (state.busy || state.step != RegistrationEntryStep.invite) return;
    if (code.trim().isEmpty) {
      state = _state(error: 'invite_required');
      return;
    }
    final revision = ++_revision;
    state = _state(inviteCode: code.trim(), busy: true);
    try {
      final result = await support
          .checkRegistration(
            handle: state.handle,
            domain: state.domain,
            inviteCode: state.inviteCode,
            checkInvite: true,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || revision != _revision) return;
      state = _state(
        check: result,
        step: result.canVerify
            ? RegistrationEntryStep.verification
            : RegistrationEntryStep.invite,
        error: result.canVerify ? null : result.reason ?? 'handle_unavailable',
      );
    } catch (_) {
      if (mounted && revision == _revision) {
        state = _state(error: 'check_failed');
      }
    }
  }

  /// An explicit existing-account entrance survives discovery outages. It grants
  /// no ownership: the normal OTP/Core Join/Recovery checks still apply.
  void continueExisting(String handle, String domain) {
    if (handle.trim().isEmpty) {
      state = _state(error: 'handle_invalid');
      return;
    }
    _revision++;
    state = RegistrationEntryState(
      handle: handle.trim().toLowerCase(),
      domain: domain.trim().toLowerCase(),
      step: RegistrationEntryStep.verification,
      existingAccountPath: true,
    );
  }

  Future<bool> prepareVerification({
    String? handle,
    String? domain,
    String? inviteCode,
    String? phone,
    String? email,
  }) async {
    if (state.busy) return false;
    final revision = ++_revision;
    final normalizedHandle = (handle ?? state.handle).trim().toLowerCase();
    final normalizedDomain = (domain ?? state.domain).trim().toLowerCase();
    final sameAccount =
        state.handle == normalizedHandle && state.domain == normalizedDomain;
    state = RegistrationEntryState(
      handle: normalizedHandle,
      domain: normalizedDomain,
      inviteCode: inviteCode?.trim() ?? (sameAccount ? state.inviteCode : ''),
      busy: true,
      existingAccountPath: sameAccount && state.existingAccountPath,
    );
    try {
      final inviteCode = state.inviteCode.trim();
      final result = await support
          .checkRegistration(
            handle: state.handle,
            domain: state.domain,
            inviteCode: inviteCode.isEmpty ? null : inviteCode,
            phone: phone,
            email: email,
            checkInvite: inviteCode.isNotEmpty,
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted || revision != _revision) return false;
      final needsInvite =
          result.decision == 'register' &&
          result.inviteRequired &&
          result.inviteStatus != 'valid';
      final missingInvite = needsInvite && inviteCode.isEmpty;
      final canVerify =
          result.canVerify && (!state.existingAccountPath || result.isExisting);
      state = _state(
        check: result,
        step: result.decision == 'unavailable' || needsInvite
            ? RegistrationEntryStep.invite
            : RegistrationEntryStep.verification,
        error: missingInvite
            ? null
            : state.existingAccountPath && !result.isExisting
            ? 'check_failed'
            : canVerify
            ? null
            : result.reason ?? 'handle_unavailable',
      );
      return canVerify;
    } catch (_) {
      if (mounted && revision == _revision) {
        state = _state(error: 'check_failed');
      }
      return false;
    }
  }
}

final registrationEntryProvider =
    StateNotifierProvider.autoDispose<
      RegistrationEntryController,
      RegistrationEntryState
    >((ref) {
      ref.watch(activeAppTenantProvider);
      return RegistrationEntryController(
        ref.watch(onboardingSupportServiceProvider),
      );
    });
