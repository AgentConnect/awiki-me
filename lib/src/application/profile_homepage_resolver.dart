import '../domain/entities/user_profile.dart';
import 'config/awiki_environment_config.dart';

class ProfileHomepageResolver {
  const ProfileHomepageResolver({required AwikiEnvironmentConfig environment})
    : _environment = environment;

  final AwikiEnvironmentConfig _environment;

  String homepageUrl(UserProfile profile) {
    final fullHandle = _cleanHandle(profile.fullHandle);
    if (fullHandle != null && _isDomainQualifiedHandle(fullHandle)) {
      return _urlForHandle(fullHandle);
    }

    final handle = _cleanHandle(profile.handle);
    if (handle != null && _isDomainQualifiedHandle(handle)) {
      return _urlForHandle(handle);
    }

    final didDomain = _didDomain(profile.did);
    if (fullHandle != null && didDomain != null) {
      return _urlForHandle('$fullHandle.$didDomain');
    }

    if (handle != null && didDomain != null) {
      return _urlForHandle('$handle.$didDomain');
    }

    final didHandle = _didHandle(profile.did);
    if (didHandle != null && didDomain != null) {
      return _urlForHandle('$didHandle.$didDomain');
    }

    if (handle != null) {
      return _urlForHandle('$handle.${_environment.didDomain}');
    }

    if (fullHandle != null) {
      return _urlForHandle('$fullHandle.${_environment.didDomain}');
    }

    return '';
  }
}

bool _isDomainQualifiedHandle(String handle) {
  return handle.contains('.');
}

String? _cleanHandle(String? value) {
  var trimmed = value?.trim().toLowerCase();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith('@')) {
    trimmed = trimmed.substring(1);
  }
  return trimmed.isEmpty ? null : trimmed;
}

String _urlForHandle(String handle) {
  return 'https://$handle';
}

String? _didDomain(String did) {
  final parts = did.trim().split(':');
  if (parts.length < 3 || parts[0] != 'did' || parts[1] != 'wba') {
    return null;
  }
  final domain = parts[2].trim().toLowerCase();
  return domain.isEmpty ? null : domain;
}

String? _didHandle(String did) {
  final parts = did.trim().split(':');
  if (parts.length < 5 || parts[0] != 'did' || parts[1] != 'wba') {
    return null;
  }
  final segment = parts[3] == 'user' && parts.length >= 6 ? parts[4] : parts[3];
  if (segment == 'agent' || segment == 'group' || segment == 'groups') {
    return null;
  }
  final handle = segment.trim().toLowerCase();
  return handle.isEmpty ? null : handle;
}
