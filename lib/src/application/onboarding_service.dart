import '../domain/entities/profile_patch.dart';
import 'app_session_service.dart';
import 'ports/identity_core_port.dart';
import 'ports/legacy_identity_upgrade_port.dart';
import 'ports/profile_core_port.dart';

abstract interface class OnboardingService {
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  );

  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  );

  Future<IdentityRegistrationResult> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  });

  Future<IdentityRegistrationResult> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  });

  Future<IdentityRegistrationResult> registerHandleWithoutContactVerification({
    required String phone,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  });
}

class ImCoreOnboardingService implements OnboardingService {
  ImCoreOnboardingService({
    required IdentityCorePort identities,
    required LegacyIdentityUpgradePort legacyUpgrades,
    required AppSessionService sessions,
    ProfileCorePort? profiles,
  }) : _identities = identities,
       _legacyUpgrades = legacyUpgrades,
       _sessions = sessions,
       _profiles = profiles;

  final IdentityCorePort _identities;
  final LegacyIdentityUpgradePort _legacyUpgrades;
  final AppSessionService _sessions;
  final ProfileCorePort? _profiles;

  @override
  Future<LegacyIdentityUpgradeStatus> legacyUpgradeStatus(
    String identityIdOrAlias,
  ) {
    return _legacyUpgrades.legacyUpgradeStatus(identityIdOrAlias);
  }

  @override
  Future<LegacyIdentityUpgradeStatus> upgradeLegacyIdentity(
    String identityIdOrAlias,
  ) {
    return _legacyUpgrades.upgradeLegacyIdentity(identityIdOrAlias);
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithPhone({
    required String phone,
    required String otp,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final result = await _identities.registerHandleWithPhone(
      phone: _normalizePhone(phone),
      otp: _sanitizeOtp(otp),
      handle: _normalizeHandle(handle),
      inviteCode: _nonEmpty(inviteCode),
      displayName: _nonEmpty(nickName),
    );
    return _activateAndPatchProfile(
      result,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithEmail({
    required String email,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    final result = await _identities.registerHandleWithEmail(
      email: email.trim().toLowerCase(),
      handle: _normalizeHandle(handle),
      inviteCode: _nonEmpty(inviteCode),
      displayName: _nonEmpty(nickName),
    );
    return _activateAndPatchProfile(
      result,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
  }

  @override
  Future<IdentityRegistrationResult> registerHandleWithoutContactVerification({
    required String phone,
    required String handle,
    String? inviteCode,
    String? nickName,
    String? profileMarkdown,
  }) async {
    _normalizePhone(phone);
    final result = await _identities.registerHandleWithoutContactVerification(
      handle: _normalizeHandle(handle),
      inviteCode: _nonEmpty(inviteCode),
      displayName: _nonEmpty(nickName),
    );
    return _activateAndPatchProfile(
      result,
      nickName: nickName,
      profileMarkdown: profileMarkdown,
    );
  }

  Future<IdentityRegistrationResult> _activateAndPatchProfile(
    IdentityRegistrationResult result, {
    String? nickName,
    String? profileMarkdown,
  }) async {
    if (result.status == IdentityRegistrationStatus.joinRequired) {
      if (result.joinProgress == null) {
        throw StateError(
          'Join-required registration did not include Join progress.',
        );
      }
      return result;
    }
    final identity = result.identity;
    if (identity == null) {
      throw StateError('Registered result did not include an identity.');
    }
    final session = await _sessions.activateIdentity(identity);
    final markdown = _nonEmpty(profileMarkdown);
    if (markdown != null && _profiles != null) {
      await _profiles.updateProfile(
        ProfilePatch(nickName: _nonEmpty(nickName), profileMarkdown: markdown),
      );
    }
    return IdentityRegistrationResult(
      status: IdentityRegistrationStatus.registered,
      identity: session,
    );
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
