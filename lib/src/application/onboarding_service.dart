import '../domain/entities/profile_patch.dart';
import 'app_session_service.dart';
import 'models/app_session.dart';
import 'ports/identity_core_port.dart';
import 'ports/profile_core_port.dart';

abstract interface class OnboardingService {
  Future<AppSession> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  });

  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  });

  Future<AppSession> registerHandleWithoutContactVerification({
    required String phone,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  });

  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
    AppSessionTransition? transition,
  });
}

class ImCoreOnboardingService implements OnboardingService {
  ImCoreOnboardingService({
    required IdentityCorePort identities,
    required AppSessionService sessions,
    ProfileCorePort? profiles,
  }) : _identities = identities,
       _sessions = sessions,
       _profiles = profiles;

  final IdentityCorePort _identities;
  final AppSessionService _sessions;
  final ProfileCorePort? _profiles;

  @override
  Future<AppSession> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) async {
    final normalizedPhone = _normalizePhone(phone);
    final normalizedOtp = _sanitizeOtp(otp);
    final normalizedHandle = _normalizeHandle(handle);
    return _runSessionTransition(transition, (requestedTransition) async {
      final identity = await _identities.registerHandleWithPhone(
        phone: normalizedPhone,
        otp: normalizedOtp,
        handle: normalizedHandle,
        inviteCode: _nonEmpty(inviteCode),
        displayName: _nonEmpty(nickName),
      );
      return _activateAndPatchProfile(
        identity,
        transition: requestedTransition,
        nickName: nickName,
        profileMarkdown: profileMarkdown,
      );
    });
  }

  @override
  Future<AppSession> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedHandle = _normalizeHandle(handle);
    return _runSessionTransition(transition, (requestedTransition) async {
      final identity = await _identities.registerHandleWithEmail(
        email: normalizedEmail,
        handle: normalizedHandle,
        inviteCode: _nonEmpty(inviteCode),
        displayName: _nonEmpty(nickName),
      );
      return _activateAndPatchProfile(
        identity,
        transition: requestedTransition,
        nickName: nickName,
        profileMarkdown: profileMarkdown,
      );
    });
  }

  @override
  Future<AppSession> recoverHandle({
    required String phone,
    required String otp,
    required String handle,
    AppSessionTransition? transition,
  }) async {
    final normalizedPhone = _normalizePhone(phone);
    final normalizedOtp = _sanitizeOtp(otp);
    final normalizedHandle = _normalizeHandle(handle);
    return _runSessionTransition(transition, (requestedTransition) async {
      final identity = await _identities.recoverHandle(
        phone: normalizedPhone,
        otp: normalizedOtp,
        handle: normalizedHandle,
      );
      return _sessions.activateIdentity(
        identity,
        transition: requestedTransition,
      );
    });
  }

  @override
  Future<AppSession> registerHandleWithoutContactVerification({
    required String phone,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
    AppSessionTransition? transition,
  }) async {
    _normalizePhone(phone);
    final normalizedHandle = _normalizeHandle(handle);
    return _runSessionTransition(transition, (requestedTransition) async {
      final identity = await _identities
          .registerHandleWithoutContactVerification(
            handle: normalizedHandle,
            inviteCode: _nonEmpty(inviteCode),
            displayName: _nonEmpty(nickName),
          );
      return _activateAndPatchProfile(
        identity,
        transition: requestedTransition,
        nickName: nickName,
        profileMarkdown: profileMarkdown,
      );
    });
  }

  Future<AppSession> _activateAndPatchProfile(
    AppSession identity, {
    required AppSessionTransition transition,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final markdown = _nonEmpty(profileMarkdown);
    return _sessions.activateIdentity(
      identity,
      transition: transition,
      initializeIdentitySession: markdown == null || _profiles == null
          ? null
          : (_) async {
              await _profiles.updateProfile(
                ProfilePatch(
                  nickName: _nonEmpty(nickName),
                  profileMarkdown: markdown,
                ),
              );
            },
    );
  }

  Future<AppSession> _runSessionTransition(
    AppSessionTransition? transition,
    Future<AppSession> Function(AppSessionTransition transition) action,
  ) async {
    final requestedTransition =
        transition ?? _sessions.beginSessionTransition();
    try {
      return await action(requestedTransition);
    } catch (_) {
      _sessions.cancelPendingSessionTransition(requestedTransition);
      rethrow;
    }
  }
}

String _normalizePhone(String phone) {
  final raw = phone.trim();
  final intlPattern = RegExp(r'^\+\d{1,3}\d{6,14}$');
  final cnLocalPattern = RegExp(r'^1[3-9]\d{9}$');
  if (raw.startsWith('+')) {
    if (!intlPattern.hasMatch(raw)) {
      throw ArgumentError('phone_invalid_intl_example');
    }
    return raw;
  }
  if (cnLocalPattern.hasMatch(raw)) {
    return '+86$raw';
  }
  throw ArgumentError('phone_invalid_intl_or_cn');
}

String _normalizeHandle(String handle) {
  final normalized = handle.trim().toLowerCase();
  final pattern = RegExp(r'^[a-z0-9-]{2,32}$');
  if (!pattern.hasMatch(normalized)) {
    throw ArgumentError('handle_invalid_pattern');
  }
  return normalized;
}

String _sanitizeOtp(String code) => code.replaceAll(RegExp(r'\s+'), '');

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
