class AppVersion {
  const AppVersion({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;

  String get displayLabel => '$version+$buildNumber';
}

class AppUpdatePlatformManifest {
  const AppUpdatePlatformManifest({
    this.downloadUrl,
    this.appcastUrl,
    this.sha256,
    this.minSupportedBuildNumber,
  });

  final String? downloadUrl;
  final String? appcastUrl;
  final String? sha256;
  final int? minSupportedBuildNumber;

  factory AppUpdatePlatformManifest.fromJson(Map<String, Object?> json) {
    return AppUpdatePlatformManifest(
      downloadUrl: _readString(json, 'downloadUrl'),
      appcastUrl: _readString(json, 'appcastUrl'),
      sha256: _readString(json, 'sha256'),
      minSupportedBuildNumber: _readInt(json, 'minSupportedBuildNumber'),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (downloadUrl != null) 'downloadUrl': downloadUrl,
      if (appcastUrl != null) 'appcastUrl': appcastUrl,
      if (sha256 != null) 'sha256': sha256,
      if (minSupportedBuildNumber != null)
        'minSupportedBuildNumber': minSupportedBuildNumber,
    };
  }
}

class AppUpdatePlatformsManifest {
  const AppUpdatePlatformsManifest({
    this.macos = const AppUpdatePlatformManifest(),
    this.android = const AppUpdatePlatformManifest(),
  });

  final AppUpdatePlatformManifest macos;
  final AppUpdatePlatformManifest android;

  factory AppUpdatePlatformsManifest.fromJson(Map<String, Object?> json) {
    return AppUpdatePlatformsManifest(
      macos: _readMap(json, 'macos') == null
          ? const AppUpdatePlatformManifest()
          : AppUpdatePlatformManifest.fromJson(_readMap(json, 'macos')!),
      android: _readMap(json, 'android') == null
          ? const AppUpdatePlatformManifest()
          : AppUpdatePlatformManifest.fromJson(_readMap(json, 'android')!),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'macos': macos.toJson(),
      'android': android.toJson(),
    };
  }
}

class AppUpdateManifest {
  const AppUpdateManifest({
    required this.version,
    required this.buildNumber,
    required this.publishedAt,
    required this.releaseNotesUrl,
    required this.githubReleaseUrl,
    required this.platforms,
  });

  final String version;
  final int buildNumber;
  final DateTime publishedAt;
  final String releaseNotesUrl;
  final String githubReleaseUrl;
  final AppUpdatePlatformsManifest platforms;

  factory AppUpdateManifest.fromJson(Map<String, Object?> json) {
    final version = _readString(json, 'version');
    final buildNumber = _readInt(json, 'buildNumber');
    final publishedAtRaw = _readString(json, 'publishedAt');
    final releaseNotesUrl = _readString(json, 'releaseNotesUrl');
    final githubReleaseUrl = _readString(json, 'githubReleaseUrl');
    final platforms = _readMap(json, 'platforms');
    if (version == null ||
        buildNumber == null ||
        publishedAtRaw == null ||
        releaseNotesUrl == null ||
        githubReleaseUrl == null ||
        platforms == null) {
      throw const FormatException('Invalid update manifest.');
    }
    return AppUpdateManifest(
      version: version,
      buildNumber: buildNumber,
      publishedAt: DateTime.parse(publishedAtRaw),
      releaseNotesUrl: releaseNotesUrl,
      githubReleaseUrl: githubReleaseUrl,
      platforms: AppUpdatePlatformsManifest.fromJson(platforms),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'buildNumber': buildNumber,
      'publishedAt': publishedAt.toUtc().toIso8601String(),
      'releaseNotesUrl': releaseNotesUrl,
      'githubReleaseUrl': githubReleaseUrl,
      'platforms': platforms.toJson(),
    };
  }
}

String? _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  return null;
}

int? _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

Map<String, Object?>? _readMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map<String, Object?>(
      (Object? mapKey, Object? mapValue) =>
          MapEntry(mapKey.toString(), mapValue),
    );
  }
  return null;
}
