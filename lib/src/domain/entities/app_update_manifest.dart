class AppVersion {
  const AppVersion({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;

  String get displayLabel => '$version+$buildNumber';
}

class AppUpdateArtifactMirror {
  const AppUpdateArtifactMirror({required this.url});

  final String url;

  factory AppUpdateArtifactMirror.fromJson(Map<String, Object?> json) {
    final url = _readString(json, 'url');
    if (url == null) {
      throw const FormatException('Update mirror URL is required.');
    }
    return AppUpdateArtifactMirror(url: url);
  }

  Map<String, Object?> toJson() => <String, Object?>{'url': url};
}

class AppUpdatePlatformManifest {
  const AppUpdatePlatformManifest({
    this.downloadUrl,
    this.appcastUrl,
    this.sha256,
    this.sizeBytes,
    this.minSupportedBuildNumber,
    this.mirrors = const <AppUpdateArtifactMirror>[],
  });

  final String? downloadUrl;
  final String? appcastUrl;
  final String? sha256;
  final int? sizeBytes;
  final int? minSupportedBuildNumber;
  final List<AppUpdateArtifactMirror> mirrors;

  factory AppUpdatePlatformManifest.fromJson(Map<String, Object?> json) {
    final mirrors = _readList(json, 'mirrors')
        .map((item) => AppUpdateArtifactMirror.fromJson(_asMap(item)))
        .toList(growable: false);
    final value = AppUpdatePlatformManifest(
      downloadUrl: _readString(json, 'downloadUrl'),
      appcastUrl: _readString(json, 'appcastUrl'),
      sha256: _readString(json, 'sha256'),
      sizeBytes: _readInt(json, 'sizeBytes'),
      minSupportedBuildNumber: _readInt(json, 'minSupportedBuildNumber'),
      mirrors: mirrors,
    );
    value.validate();
    return value;
  }

  void validate() {
    if (downloadUrl != null) {
      if (sha256 == null || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256!)) {
        throw const FormatException(
          'Download artifacts require a SHA-256 digest.',
        );
      }
      if (sizeBytes == null || sizeBytes! <= 0) {
        throw const FormatException(
          'Download artifacts require a positive file size.',
        );
      }
    }
    if (mirrors.isNotEmpty && downloadUrl == null) {
      throw const FormatException('Mirrors require a primary download URL.');
    }
  }

  List<String> get downloadCandidates => <String>[
    if (downloadUrl != null) downloadUrl!,
    ...mirrors.map((item) => item.url),
  ];

  Map<String, Object?> toJson() => <String, Object?>{
    if (downloadUrl != null) 'downloadUrl': downloadUrl,
    if (appcastUrl != null) 'appcastUrl': appcastUrl,
    if (sha256 != null) 'sha256': sha256,
    if (sizeBytes != null) 'sizeBytes': sizeBytes,
    if (minSupportedBuildNumber != null)
      'minSupportedBuildNumber': minSupportedBuildNumber,
    if (mirrors.isNotEmpty)
      'mirrors': mirrors.map((item) => item.toJson()).toList(growable: false),
  };
}

class AppUpdatePlatformsManifest {
  const AppUpdatePlatformsManifest({
    this.macos = const AppUpdatePlatformManifest(),
    this.android = const AppUpdatePlatformManifest(),
    this.windows = const AppUpdatePlatformManifest(),
  });

  final AppUpdatePlatformManifest macos;
  final AppUpdatePlatformManifest android;
  final AppUpdatePlatformManifest windows;

  factory AppUpdatePlatformsManifest.fromJson(Map<String, Object?> json) {
    AppUpdatePlatformManifest read(String key) {
      final value = _readMap(json, key);
      return value == null
          ? const AppUpdatePlatformManifest()
          : AppUpdatePlatformManifest.fromJson(value);
    }

    return AppUpdatePlatformsManifest(
      macos: read('macos'),
      android: read('android'),
      windows: _readMap(json, 'windows-x64') != null
          ? read('windows-x64')
          : read('windows'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'macos': macos.toJson(),
    'android': android.toJson(),
    'windows-x64': windows.toJson(),
  };
}

class AppUpdateManifest {
  const AppUpdateManifest({
    this.product = 'awiki-me',
    this.channel = 'stable',
    required this.policyOrigin,
    required this.policyRevision,
    required this.version,
    required this.buildNumber,
    required this.minimumSupportedVersion,
    required this.minimumSupportedBuildNumber,
    required this.publishedAt,
    required this.releaseNotesUrl,
    required this.githubReleaseUrl,
    required this.platforms,
  });

  final String product;
  final String channel;
  final String policyOrigin;
  final int policyRevision;
  final String version;
  final int buildNumber;
  final String minimumSupportedVersion;
  final int minimumSupportedBuildNumber;
  final DateTime publishedAt;
  final String releaseNotesUrl;
  final String githubReleaseUrl;
  final AppUpdatePlatformsManifest platforms;

  factory AppUpdateManifest.fromJson(Map<String, Object?> json) {
    final product = _readString(json, 'product');
    final channel = _readString(json, 'channel');
    final policyOrigin = _readString(json, 'policy_origin');
    final policyRevision = _readInt(json, 'policy_revision');
    final version = _readString(json, 'version');
    final buildNumber = _readInt(json, 'buildNumber');
    final minimumSupportedVersion = _readString(
      json,
      'minimum_supported_version',
    );
    final minimumSupportedBuildNumber = _readInt(
      json,
      'minimum_supported_build_number',
    );
    final publishedAtRaw =
        _readString(json, 'published_at') ?? _readString(json, 'publishedAt');
    final releaseNotesUrl =
        _readString(json, 'release_notes_url') ??
        _readString(json, 'releaseNotesUrl');
    final githubReleaseUrl = _readString(json, 'githubReleaseUrl');
    final platforms = _readMap(json, 'platforms');
    if (product == null ||
        channel == null ||
        policyOrigin == null ||
        policyRevision == null ||
        version == null ||
        buildNumber == null ||
        minimumSupportedVersion == null ||
        minimumSupportedBuildNumber == null ||
        publishedAtRaw == null ||
        releaseNotesUrl == null ||
        githubReleaseUrl == null ||
        platforms == null) {
      throw const FormatException('Invalid update manifest.');
    }
    if (product != 'awiki-me' || channel != 'stable' || policyRevision < 1) {
      throw const FormatException('Invalid update policy identity.');
    }
    return AppUpdateManifest(
      product: product,
      channel: channel,
      policyOrigin: _normalizedOrigin(policyOrigin),
      policyRevision: policyRevision,
      version: _validatedVersion(version),
      buildNumber: buildNumber,
      minimumSupportedVersion: _validatedVersion(minimumSupportedVersion),
      minimumSupportedBuildNumber: minimumSupportedBuildNumber,
      publishedAt: DateTime.parse(publishedAtRaw),
      releaseNotesUrl: releaseNotesUrl,
      githubReleaseUrl: githubReleaseUrl,
      platforms: AppUpdatePlatformsManifest.fromJson(platforms),
    );
  }

  int minimumBuildForPlatform(String platform) {
    final platformMinimum = switch (platform) {
      'android' => platforms.android.minSupportedBuildNumber,
      'macos' => platforms.macos.minSupportedBuildNumber,
      'windows' => platforms.windows.minSupportedBuildNumber,
      _ => null,
    };
    return platformMinimum ?? minimumSupportedBuildNumber;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'product': product,
    'channel': channel,
    'policy_origin': policyOrigin,
    'policy_revision': policyRevision,
    'version': version,
    'buildNumber': buildNumber,
    'minimum_supported_version': minimumSupportedVersion,
    'minimum_supported_build_number': minimumSupportedBuildNumber,
    'published_at': publishedAt.toUtc().toIso8601String(),
    'release_notes_url': releaseNotesUrl,
    'githubReleaseUrl': githubReleaseUrl,
    'platforms': platforms.toJson(),
  };
}

int compareAppVersions(String left, String right) {
  final a = _SemanticVersion.parse(left);
  final b = _SemanticVersion.parse(right);
  for (var index = 0; index < 3; index += 1) {
    final compared = a.core[index].compareTo(b.core[index]);
    if (compared != 0) return compared;
  }
  if (a.prerelease == null && b.prerelease == null) return 0;
  if (a.prerelease == null) return 1;
  if (b.prerelease == null) return -1;
  final shared = a.prerelease!.length < b.prerelease!.length
      ? a.prerelease!.length
      : b.prerelease!.length;
  for (var index = 0; index < shared; index += 1) {
    final leftPart = a.prerelease![index];
    final rightPart = b.prerelease![index];
    if (leftPart == rightPart) continue;
    final leftNumber = int.tryParse(leftPart);
    final rightNumber = int.tryParse(rightPart);
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    if (leftNumber != null) return -1;
    if (rightNumber != null) return 1;
    return leftPart.compareTo(rightPart);
  }
  return a.prerelease!.length.compareTo(b.prerelease!.length);
}

class _SemanticVersion {
  const _SemanticVersion(this.core, this.prerelease);

  final List<int> core;
  final List<String>? prerelease;

  static _SemanticVersion parse(String value) {
    final validated = _validatedVersion(value);
    final withoutBuild = validated.split('+').first;
    final dash = withoutBuild.indexOf('-');
    final coreText = dash < 0 ? withoutBuild : withoutBuild.substring(0, dash);
    final prerelease = dash < 0
        ? null
        : withoutBuild.substring(dash + 1).split('.');
    return _SemanticVersion(
      coreText.split('.').map(int.parse).toList(growable: false),
      prerelease,
    );
  }
}

String _validatedVersion(String value) {
  final match = RegExp(
    r'^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  ).firstMatch(value);
  final prerelease = match?.group(4);
  if (match == null ||
      (prerelease != null &&
          prerelease
              .split('.')
              .any(
                (part) =>
                    int.tryParse(part) != null &&
                    part.length > 1 &&
                    part.startsWith('0'),
              ))) {
    throw FormatException('Invalid semantic version: $value');
  }
  return value;
}

String _normalizedOrigin(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      !uri.hasScheme ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.path.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException('Invalid policy origin.');
  }
  return uri.origin;
}

String? _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

int? _readInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  return value is String ? int.tryParse(value) : null;
}

Map<String, Object?>? _readMap(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is Map ? _asMap(value) : null;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map) throw const FormatException('Expected JSON object.');
  return value.map<String, Object?>(
    (key, item) => MapEntry(key.toString(), item),
  );
}

List<Object?> _readList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const <Object?>[];
  if (value is! List) throw const FormatException('Expected JSON array.');
  return value.cast<Object?>();
}
