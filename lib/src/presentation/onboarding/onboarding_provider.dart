import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_services.dart';
import '../../app/ui_feedback.dart';
import '../../l10n/app_message.dart';
import '../app_shell/providers/app_runtime_provider.dart';

class OnboardingState {
  const OnboardingState({
    this.entryMode = 'login',
    this.authMode = 'phone',
    this.registerStep = 1,
    this.emailVerified = false,
    this.isBusy = false,
  });

  final String entryMode;
  final String authMode;
  final int registerStep;
  final bool emailVerified;
  final bool isBusy;

  OnboardingState copyWith({
    String? entryMode,
    String? authMode,
    int? registerStep,
    bool? emailVerified,
    bool? isBusy,
  }) {
    return OnboardingState(
      entryMode: entryMode ?? this.entryMode,
      authMode: authMode ?? this.authMode,
      registerStep: registerStep ?? this.registerStep,
      emailVerified: emailVerified ?? this.emailVerified,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

class OnboardingController extends StateNotifier<OnboardingState> {
  OnboardingController(this.ref) : super(const OnboardingState());

  final Ref ref;
  static const Duration _requestTimeout = Duration(seconds: 20);

  void setEntryMode(String value) {
    state = state.copyWith(
      entryMode: value,
      registerStep: value == 'login' ? 1 : state.registerStep,
    );
  }

  void setAuthMode(String value) {
    state = state.copyWith(authMode: value, emailVerified: false);
  }

  void setRegisterStep(int step) {
    state = state.copyWith(registerStep: step);
  }

  Future<void> requestOtp(String phone) async {
    await _runBusy(() => ref.read(awikiGatewayProvider).sendOtp(phone: phone));
  }

  Future<void> requestEmailActivation(String email) async {
    await _runBusy(
      () => ref.read(awikiGatewayProvider).sendEmailVerification(email: email),
    );
  }

  Future<bool> checkEmailActivation(String email) async {
    var verified = false;
    await _runBusy(() async {
      verified =
          await ref.read(awikiGatewayProvider).checkEmailVerified(email: email);
      if (!verified) {
        ref
            .read(uiFeedbackProvider.notifier)
            .showError(AppMessage.emailNotActivatedClickLink());
      }
    });
    state = state.copyWith(emailVerified: verified);
    return verified;
  }

  Future<void> registerWithPhone({
    required String phone,
    required String otp,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    await _runBusy(() async {
      final session = await ref.read(awikiGatewayProvider).registerHandle(
            phone: phone,
            otp: otp,
            handle: handle,
            nickName: nickName,
            profileMarkdown: profileMarkdown,
          );
      await ref.read(appRuntimeProvider.notifier).activateSession(session);
    });
  }

  Future<void> loginExistingWithOtp({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    await _runBusy(() async {
      final session = await ref.read(awikiGatewayProvider).recoverHandle(
            phone: phone,
            otp: otp,
            handle: handle,
          );
      await ref.read(appRuntimeProvider.notifier).activateSession(session);
    });
  }

  Future<void> registerWithEmail({
    required String email,
    required String handle,
    required String nickName,
    required String profileMarkdown,
  }) async {
    await _runBusy(() async {
      final verified =
          await ref.read(awikiGatewayProvider).checkEmailVerified(email: email);
      if (!verified) {
        throw StateError('邮箱尚未激活，请先点击邮件中的激活链接。');
      }
      final session =
          await ref.read(awikiGatewayProvider).registerHandleWithEmail(
                email: email,
                handle: handle,
                nickName: nickName,
                profileMarkdown: profileMarkdown,
              );
      await ref.read(appRuntimeProvider.notifier).activateSession(session);
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    state = state.copyWith(isBusy: true);
    try {
      await action().timeout(_requestTimeout);
    } on TimeoutException {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.requestTimeoutRetry());
    } catch (error) {
      ref
          .read(uiFeedbackProvider.notifier)
          .showError(AppMessage.fromError(error));
    } finally {
      state = state.copyWith(isBusy: false);
    }
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingController, OnboardingState>(
  (ref) => OnboardingController(ref),
);
