import '../../application/app_session_service.dart';
import '../../application/models/app_session.dart';
import '../../application/onboarding_service.dart';
import '../../application/onboarding_support_service.dart';
import '../../domain/entities/session_identity.dart';
import '../../domain/repositories/awiki_account_gateway.dart';

class CompatAwikiAccountGateway implements AwikiAccountGateway {
  CompatAwikiAccountGateway({
    required AppSessionService sessions,
    required OnboardingService onboarding,
    OnboardingSupportService? onboardingSupport,
  }) : _sessions = sessions,
       _onboarding = onboarding,
       _onboardingSupport = onboardingSupport;

  final AppSessionService _sessions;
  final OnboardingService _onboarding;
  final OnboardingSupportService? _onboardingSupport;

  @override
  Future<SessionIdentity?> restoreSession() async {
    return (await _sessions.restoreSession())?.toLegacySessionIdentity();
  }

  @override
  Future<SessionIdentity?> currentSession() async {
    return (await _sessions.currentSession())?.toLegacySessionIdentity();
  }

  @override
  Future<SessionIdentity?> refreshSession() async {
    return (await _sessions.refreshSession())?.toLegacySessionIdentity();
  }

  @override
  Future<Object> currentAnpSession({bool requireSigning = false}) {
    throw UnsupportedError(
      'IM Core currentAnpSession is not available in awiki-me compatibility mode',
    );
  }

  @override
  Future<void> logout() {
    return _sessions.logout();
  }

  @override
  Future<List<SessionIdentity>> listLocalCredentials() async {
    final identities = await _sessions.listLocalIdentities();
    return identities
        .map((identity) => identity.toLegacySessionIdentity())
        .toList()
      ..sort((a, b) => a.credentialName.compareTo(b.credentialName));
  }

  @override
  Future<SessionIdentity> loginWithLocalCredential(String credentialName) {
    // TODO(im-core): enable after SDK active/default identity APIs and
    // awiki-me activeIdentityId preference are in place.
    throw UnsupportedError(
      'IM Core explicit local credential login is not available yet',
    );
  }

  @override
  Future<void> deleteLocalCredential(String credentialName) {
    // TODO(im-core): enable after SDK identity delete API is exposed.
    throw UnsupportedError(
      'IM Core local credential delete is not available yet',
    );
  }

  @override
  Future<String?> exportCurrentCredentialAsZip() {
    // TODO(im-core): enable after SDK identity export API is exposed.
    throw UnsupportedError(
      'IM Core local credential export is not available yet',
    );
  }

  @override
  Future<SessionIdentity?> importCredentialFromZip() {
    // TODO(im-core): enable after SDK identity import API is exposed.
    throw UnsupportedError(
      'IM Core local credential import is not available yet',
    );
  }

  @override
  Future<void> sendOtp({required String phone}) {
    final support = _onboardingSupport;
    if (support == null) {
      // TODO(im-core): route OTP request through SDK once exposed.
      throw UnsupportedError('IM Core sendOtp is not available yet');
    }
    return support.sendOtp(phone: phone);
  }

  @override
  Future<void> sendEmailVerification({required String email}) {
    final support = _onboardingSupport;
    if (support == null) {
      // TODO(im-core): route email verification request through SDK once exposed.
      throw UnsupportedError(
        'IM Core sendEmailVerification is not available yet',
      );
    }
    return support.sendEmailVerification(email: email);
  }

  @override
  Future<bool> checkEmailVerified({required String email}) {
    final support = _onboardingSupport;
    if (support == null) {
      // TODO(im-core): route email verification polling through SDK once exposed.
      throw UnsupportedError('IM Core checkEmailVerified is not available yet');
    }
    return support.checkEmailVerified(email: email);
  }

  @override
  Future<HandleRegistrationStatus> lookupHandleRegistration({
    required String handle,
  }) {
    final support = _onboardingSupport;
    if (support == null) {
      // TODO(im-core): expose unauthenticated handle lookup or onboarding lookup.
      throw UnsupportedError(
        'IM Core lookupHandleRegistration is not available yet',
      );
    }
    return support.lookupHandleRegistration(handle: handle);
  }

  @override
  Future<SessionIdentity> registerHandle({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final session = await _onboarding.registerHandleWithPhone(
      phone: phone,
      otp: otp,
      handle: handle,
      inviteCode: inviteCode,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
    return session.toLegacySessionIdentity();
  }

  @override
  Future<SessionIdentity> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final session = await _onboarding.registerHandleWithEmail(
      email: email,
      handle: handle,
      inviteCode: inviteCode,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
    return session.toLegacySessionIdentity();
  }

  @override
  Future<SessionIdentity> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
  }) async {
    final session = await _onboarding.recoverHandle(
      phone: phone,
      otp: otp,
      handle: handle,
    );
    return session.toLegacySessionIdentity();
  }
}

extension AppSessionLegacyMapping on AppSession {
  SessionIdentity toLegacySessionIdentity() {
    return SessionIdentity(
      did: did,
      credentialName: localAlias ?? identityId,
      displayName: displayName,
      handle: handle,
      jwtToken: null,
    );
  }
}
