import 'dart:async';
import 'dart:convert';

import 'package:awiki_me/src/data/services/app_key_value_store.dart';
import 'package:awiki_me/src/data/services/app_update_service.dart';
import 'package:awiki_me/src/data/services/platform_update_bridge.dart';
import 'package:awiki_me/src/domain/entities/app_update_manifest.dart';
import 'package:awiki_me/src/domain/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('checkForUpdates fetches manifest and caches it', () async {
    final storage = _MemoryKeyValueStore();
    final httpClient = _QueueHttpClient(<_HttpFixture>[
      _HttpFixture.json(
        'https://updates.example/latest.json',
        _manifestJson(buildNumber: 12),
      ),
    ]);
    final service = _service(storage: storage, httpClient: httpClient);

    final result = await service.checkForUpdates(force: true);

    expect(result.wasSkipped, isFalse);
    expect(result.currentVersion.displayLabel, '1.0.0+10');
    expect(result.latestManifest?.version, '1.2.0');
    expect(result.hasUpdate, isTrue);
    expect(httpClient.requestedUrls, <String>[
      'https://updates.example/latest.json',
    ]);
    expect(
      storage.values['awiki_me_update_last_manifest'],
      contains('"buildNumber":12'),
    );
    expect(storage.values['awiki_me_update_last_checked_at'], isNotNull);
  });

  test('auto check uses fresh cached manifest without network', () async {
    final storage = _MemoryKeyValueStore(<String, String>{
      'awiki_me_update_last_checked_at': DateTime.now()
          .toUtc()
          .toIso8601String(),
      'awiki_me_update_last_manifest': jsonEncode(
        AppUpdateManifest.fromJson(_manifestJson(buildNumber: 15)).toJson(),
      ),
    });
    final httpClient = _QueueHttpClient(const <_HttpFixture>[]);
    final service = _service(storage: storage, httpClient: httpClient);

    final result = await service.checkForUpdates(force: false);

    expect(result.wasSkipped, isTrue);
    expect(result.latestManifest?.buildNumber, 15);
    expect(result.hasUpdate, isTrue);
    expect(httpClient.requestedUrls, isEmpty);
  });

  test('auto check falls back to cached manifest when request fails', () async {
    final storage = _MemoryKeyValueStore(<String, String>{
      'awiki_me_update_last_manifest': jsonEncode(
        AppUpdateManifest.fromJson(_manifestJson(buildNumber: 13)).toJson(),
      ),
    });
    final httpClient = _QueueHttpClient(<_HttpFixture>[
      _HttpFixture.text('https://updates.example/latest.json', 503, 'down'),
    ]);
    final service = _service(storage: storage, httpClient: httpClient);

    final result = await service.checkForUpdates(force: false);

    expect(result.wasSkipped, isFalse);
    expect(result.latestManifest?.buildNumber, 13);
    expect(result.hasUpdate, isTrue);
  });

  test('force check surfaces manifest request errors', () async {
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: _QueueHttpClient(<_HttpFixture>[
        _HttpFixture.text('https://updates.example/latest.json', 500, 'boom'),
      ]),
    );

    await expectLater(
      service.checkForUpdates(force: true),
      throwsA(isA<UpdateInstallFailed>()),
    );
  });

  test('release links use manifest URL or configured fallback', () async {
    final opened = <Uri>[];
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: _QueueHttpClient(const <_HttpFixture>[]),
      urlLauncher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    final manifest = AppUpdateManifest.fromJson(_manifestJson());

    await service.openReleaseNotes(manifest);
    await service.openDownloadPage(null);

    expect(opened.map((uri) => uri.toString()), <String>[
      'https://updates.example/releases/1.2.0',
      'https://updates.example/releases',
    ]);
  });

  test('non-mobile install opens download page', () async {
    final opened = <Uri>[];
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: _QueueHttpClient(const <_HttpFixture>[]),
      urlLauncher: (uri) async {
        opened.add(uri);
        return true;
      },
    );

    await service.installUpdate(AppUpdateManifest.fromJson(_manifestJson()));

    expect(opened.single.toString(), 'https://updates.example/releases/1.2.0');
  });

  test('open URL failures are reported clearly', () async {
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: _QueueHttpClient(const <_HttpFixture>[]),
      urlLauncher: (_) async => false,
    );

    await expectLater(
      service.openDownloadPage(null),
      throwsA(isA<UpdateInstallFailed>()),
    );
  });
}

AppUpdateService _service({
  required AppKeyValueStore storage,
  required http.Client httpClient,
  Future<bool> Function(Uri uri)? urlLauncher,
}) {
  return AppUpdateService(
    storage: storage,
    httpClient: httpClient,
    platformBridge: _FakePlatformUpdateBridge(),
    packageInfoLoader: () async => PackageInfo(
      appName: 'AWiki Me',
      packageName: 'ai.awiki.awikime',
      version: '1.0.0',
      buildNumber: '10',
    ),
    urlLauncher: urlLauncher ?? (_) async => true,
    manifestUrl: 'https://updates.example/latest.json',
    releasesUrl: 'https://updates.example/releases',
  );
}

Map<String, Object?> _manifestJson({int buildNumber = 12}) {
  return <String, Object?>{
    'version': '1.2.0',
    'buildNumber': buildNumber,
    'publishedAt': '2026-06-15T01:02:03.000Z',
    'releaseNotesUrl': 'https://updates.example/releases/1.2.0',
    'githubReleaseUrl': 'https://updates.example/releases/1.2.0',
    'platforms': <String, Object?>{
      'macos': <String, Object?>{
        'appcastUrl': 'https://updates.example/appcast.xml',
      },
      'android': <String, Object?>{
        'downloadUrl': 'https://updates.example/awiki-me.apk',
        'sha256': 'abc123',
      },
    },
  };
}

class _MemoryKeyValueStore implements AppKeyValueStore {
  _MemoryKeyValueStore([Map<String, String>? initial])
    : values = Map<String, String>.from(initial ?? const <String, String>{});

  final Map<String, String> values;

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }
}

class _FakePlatformUpdateBridge implements PlatformUpdateBridge {
  @override
  Future<bool> canRequestPackageInstalls() async => true;

  @override
  Future<void> installApk(String filePath) async {}

  @override
  Future<void> openInstallPermissionSettings() async {}
}

class _QueueHttpClient extends http.BaseClient {
  _QueueHttpClient(List<_HttpFixture> fixtures) : _fixtures = List.of(fixtures);

  final List<_HttpFixture> _fixtures;
  final List<String> requestedUrls = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUrls.add(request.url.toString());
    if (_fixtures.isEmpty) {
      throw StateError('Unexpected request: ${request.url}');
    }
    final fixture = _fixtures.removeAt(0);
    expect(request.url.toString(), fixture.url);
    return http.StreamedResponse(
      Stream<List<int>>.value(fixture.bodyBytes),
      fixture.statusCode,
      headers: fixture.headers,
    );
  }
}

class _HttpFixture {
  const _HttpFixture({
    required this.url,
    required this.statusCode,
    required this.bodyBytes,
    this.headers = const <String, String>{},
  });

  factory _HttpFixture.json(String url, Map<String, Object?> body) {
    return _HttpFixture(
      url: url,
      statusCode: 200,
      bodyBytes: utf8.encode(jsonEncode(body)),
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }

  factory _HttpFixture.text(String url, int statusCode, String body) {
    return _HttpFixture(
      url: url,
      statusCode: statusCode,
      bodyBytes: utf8.encode(body),
    );
  }

  final String url;
  final int statusCode;
  final List<int> bodyBytes;
  final Map<String, String> headers;
}
