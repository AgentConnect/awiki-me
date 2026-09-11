import 'dart:async';
import 'dart:convert';

import 'package:awiki_me/src/application/config/awiki_environment_config.dart';
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

  test(
    'null version policy preserves a verified minimum across restart',
    () async {
      final storage = _MemoryKeyValueStore();
      final service = _service(
        storage: storage,
        httpClient: _QueueHttpClient([
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(policyRevision: 9, minimumVersion: '2.0.0'),
          ),
          _HttpFixture.json(
            'https://updates.example/latest.json',
            <String, Object?>{'schema_version': 1, 'client_versions': null},
          ),
        ]),
      );
      expect(
        (await service.checkForUpdates(force: true)).versionUnsupported,
        isTrue,
      );
      final result = await service.checkForUpdates(force: true);
      expect(result.versionUnsupported, isTrue);
      expect(result.usedCache, isTrue);
      expect(result.policyUnavailable, isFalse);
      expect(result.failureReason, isNotNull);
      final restarted = _service(
        storage: storage,
        httpClient: _QueueHttpClient([]),
      );
      expect((await restarted.loadCachedUpdate()).versionUnsupported, isTrue);
    },
  );

  test(
    'null version policy without cache is a check failure, not confirmed absence',
    () async {
      final storage = _MemoryKeyValueStore();
      final service = _service(
        storage: storage,
        httpClient: _QueueHttpClient([
          _HttpFixture.json(
            'https://updates.example/latest.json',
            <String, Object?>{'schema_version': 1, 'client_versions': null},
          ),
        ]),
      );
      await expectLater(
        service.checkForUpdates(force: true),
        throwsFormatException,
      );
      expect(storage.values, isEmpty);
    },
  );

  test('default update URLs follow the default AWiki environment', () {
    final baseUrl = primaryTenantBaseUrl;
    expect(
      kDefaultUpdateManifestUrl,
      '$baseUrl/user-service/v1/server-info?client_platform=app',
    );
    expect(kDefaultReleasesUrl, '$baseUrl/#download');
  });

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
    expect(storage.values.values, contains(contains('"buildNumber":12')));
    expect(
      storage.values.keys.any((key) => key.endsWith('_checked_at')),
      isTrue,
    );
  });

  test('auto check uses fresh cached manifest without network', () async {
    final storage = _MemoryKeyValueStore();
    final warmClient = _QueueHttpClient(<_HttpFixture>[
      _HttpFixture.json(
        'https://updates.example/latest.json',
        _manifestJson(buildNumber: 15),
      ),
    ]);
    await _service(
      storage: storage,
      httpClient: warmClient,
    ).checkForUpdates(force: true);
    final httpClient = _QueueHttpClient(const <_HttpFixture>[]);
    final service = _service(storage: storage, httpClient: httpClient);

    final result = await service.checkForUpdates(force: false);

    expect(result.wasSkipped, isTrue);
    expect(result.latestManifest?.buildNumber, 15);
    expect(result.hasUpdate, isTrue);
    expect(httpClient.requestedUrls, isEmpty);
  });

  test(
    'auto check refreshes a cached policy that currently locks the app',
    () async {
      final storage = _MemoryKeyValueStore();
      await _service(
        storage: storage,
        httpClient: _QueueHttpClient(<_HttpFixture>[
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(minimumVersion: '2.0.0'),
          ),
        ]),
      ).checkForUpdates(force: true);
      final httpClient = _QueueHttpClient(<_HttpFixture>[
        _HttpFixture.json(
          'https://updates.example/latest.json',
          _manifestJson(policyRevision: 5, minimumVersion: '1.0.0'),
        ),
      ]);

      final result = await _service(
        storage: storage,
        httpClient: httpClient,
      ).checkForUpdates(force: false);

      expect(result.wasSkipped, isFalse);
      expect(result.versionUnsupported, isFalse);
      expect(httpClient.requestedUrls, hasLength(1));
    },
  );

  test('auto check falls back to cached manifest when request fails', () async {
    final storage = _MemoryKeyValueStore();
    await _service(
      storage: storage,
      httpClient: _QueueHttpClient(<_HttpFixture>[
        _HttpFixture.json(
          'https://updates.example/latest.json',
          _manifestJson(buildNumber: 13),
        ),
      ]),
    ).checkForUpdates(force: true);
    storage.values.removeWhere((key, _) => key.endsWith('_checked_at'));
    final httpClient = _QueueHttpClient(<_HttpFixture>[
      _HttpFixture.text('https://updates.example/latest.json', 503, 'down'),
    ]);
    final service = _service(storage: storage, httpClient: httpClient);

    final result = await service.checkForUpdates(force: false);

    expect(result.wasSkipped, isFalse);
    expect(result.latestManifest?.buildNumber, 13);
    expect(result.hasUpdate, isTrue);
    expect(result.usedCache, isTrue);
    expect(result.failureReason, contains('503'));
  });

  test('tenant cache cannot satisfy another tenant policy check', () async {
    final storage = _MemoryKeyValueStore();
    await _service(
      storage: storage,
      httpClient: _QueueHttpClient(<_HttpFixture>[
        _HttpFixture.json(
          'https://updates.example/latest.json',
          _manifestJson(),
        ),
      ]),
      tenantId: 'china',
    ).checkForUpdates(force: true);

    await expectLater(
      _service(
        storage: storage,
        httpClient: _QueueHttpClient(<_HttpFixture>[
          _HttpFixture.text('https://updates.example/latest.json', 503, 'down'),
        ]),
        tenantId: 'global',
      ).checkForUpdates(force: true),
      throwsA(isA<UpdateInstallFailed>()),
    );
  });

  test(
    'revision rollback is rejected and current tenant cache is kept',
    () async {
      final storage = _MemoryKeyValueStore();
      final service = _service(
        storage: storage,
        httpClient: _QueueHttpClient(<_HttpFixture>[
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(policyRevision: 9, buildNumber: 15),
          ),
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(policyRevision: 8, buildNumber: 16),
          ),
        ]),
      );
      await service.checkForUpdates(force: true);

      final result = await service.checkForUpdates(force: true);

      expect(result.latestManifest?.buildNumber, 15);
      expect(result.usedCache, isTrue);
      expect(result.failureReason, contains('revision moved backwards'));
    },
  );

  test('minimum version restriction comes only from selected policy', () async {
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: _QueueHttpClient(<_HttpFixture>[
        _HttpFixture.json(
          'https://updates.example/latest.json',
          _manifestJson(minimumVersion: '1.1.0'),
        ),
      ]),
    );

    final result = await service.checkForUpdates(force: true);

    expect(result.versionUnsupported, isTrue);
  });

  test('custom tenant 404 means no automatic policy and no gate', () async {
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: _QueueHttpClient(<_HttpFixture>[
        _HttpFixture.text(
          'https://updates.example/latest.json',
          404,
          'missing',
        ),
      ]),
      officialTenant: false,
    );

    final result = await service.checkForUpdates(force: true);

    expect(result.policyUnavailable, isTrue);
    expect(result.versionUnsupported, isFalse);
  });

  test('custom tenant 404 clears an earlier minimum-version cache', () async {
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: _QueueHttpClient(<_HttpFixture>[
        _HttpFixture.json(
          'https://updates.example/latest.json',
          _manifestJson(minimumVersion: '2.0.0'),
        ),
        _HttpFixture.text(
          'https://updates.example/latest.json',
          404,
          'missing',
        ),
      ]),
      officialTenant: false,
    );
    expect(
      (await service.checkForUpdates(force: true)).versionUnsupported,
      isTrue,
    );

    final result = await service.checkForUpdates(force: true);

    expect(result.policyUnavailable, isTrue);
    expect(result.versionUnsupported, isFalse);
    expect(result.latestManifest, isNull);
    expect(result.usedCache, isFalse);
  });

  test(
    'custom tenant can explicitly check either isolated official source',
    () async {
      final storage = _MemoryKeyValueStore();
      final service = _service(
        storage: storage,
        httpClient: _QueueHttpClient(<_HttpFixture>[
          _HttpFixture.json(
            'https://awiki.ai/user-service/v1/server-info?client_platform=app',
            _serverInfoJson(
              origin: 'https://awiki.ai',
              minimumVersion: '2.0.0',
            ),
          ),
        ]),
        officialTenant: false,
      );

      final result = await service.checkOfficialSource(
        AppOfficialUpdateSource.secondary,
      );

      expect(result.latestManifest?.policyOrigin, 'https://awiki.ai');
      expect(result.versionUnsupported, isFalse);
      expect(
        await service.loadPreferredOfficialSource(),
        AppOfficialUpdateSource.secondary,
      );
    },
  );

  test('unified server-info maps the current platform download page', () async {
    final storage = _MemoryKeyValueStore();
    final client = _QueueHttpClient(<_HttpFixture>[
      _HttpFixture.json(
        'https://updates.example/user-service/v1/server-info?client_platform=app',
        _serverInfoJson(),
      ),
    ]);
    final service = AppUpdateService(
      storage: storage,
      tenantId: 'tenant-test',
      backendBaseUrl: 'https://updates.example/backend',
      httpClient: client,
      platformBridge: _FakePlatformUpdateBridge(),
      packageInfoLoader: () async => PackageInfo(
        appName: 'AWiki Me',
        packageName: 'ai.awiki.awikime',
        version: '1.0.0',
        buildNumber: '10',
      ),
      urlLauncher: (_) async => true,
    );

    final result = await service.checkForUpdates(force: true);

    expect(result.latestManifest?.version, '1.2.0');
    expect(result.latestManifest?.githubReleaseUrl, isNotEmpty);
    expect(result.hasUpdate, isTrue);
  });

  test(
    'ignored recommendation state is isolated by tenant and version',
    () async {
      final storage = _MemoryKeyValueStore();
      final manifest = AppUpdateManifest.fromJson(_manifestJson());
      final china = _service(
        storage: storage,
        httpClient: _QueueHttpClient(const <_HttpFixture>[]),
        tenantId: 'china',
      );
      final global = _service(
        storage: storage,
        httpClient: _QueueHttpClient(const <_HttpFixture>[]),
        tenantId: 'global',
      );

      await china.markVersionPrompted(manifest);
      await china.ignoreVersion(manifest);

      expect(await china.isVersionIgnored(manifest), isTrue);
      expect(await global.isVersionIgnored(manifest), isFalse);
    },
  );

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

  test('macOS manifest can expose direct DMG download without appcast', () {
    final manifest = AppUpdateManifest.fromJson(
      _manifestJson(macosAppcastUrl: null),
    );

    expect(
      manifest.platforms.macos.downloadUrl,
      'https://updates.example/awiki-me.dmg',
    );
    expect(manifest.platforms.macos.appcastUrl, isNull);
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

  test(
    'reads a cached restriction without starting network discovery',
    () async {
      final store = _MemoryKeyValueStore();
      await _service(
        storage: store,
        httpClient: _QueueHttpClient([
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(minimumVersion: '2.0.0'),
          ),
        ]),
      ).checkForUpdates(force: true);
      final client = _PendingHttpClient();
      final cached = await _service(
        storage: store,
        httpClient: client,
      ).loadCachedUpdate();
      expect(cached.versionUnsupported, isTrue);
      expect(cached.usedCache, isTrue);
      expect(client.pending, isEmpty);
    },
  );

  test('coalesces simultaneous network checks for the same tenant', () async {
    final client = _PendingHttpClient();
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: client,
    );
    final first = service.checkForUpdates(force: false);
    final second = service.checkForUpdates(force: true);
    await client.started(1);
    client.complete(0, _manifestJson());
    final results = await Future.wait([first, second]);
    expect(client.pending, hasLength(1));
    expect(
      results.every((value) => value.latestManifest?.policyRevision == 4),
      isTrue,
    );
  });

  test(
    'a forced check does not settle for a concurrent automatic cache read',
    () async {
      final store = _MemoryKeyValueStore();
      await _service(
        storage: store,
        httpClient: _QueueHttpClient([
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(),
          ),
        ]),
      ).checkForUpdates(force: true);
      final client = _PendingHttpClient();
      final service = _service(storage: store, httpClient: client);
      final automatic = service.checkForUpdates(force: false);
      final forced = service.checkForUpdates(force: true);
      await client.started(1);
      client.complete(0, _manifestJson(policyRevision: 5));
      expect((await automatic).wasSkipped, isTrue);
      expect((await forced).latestManifest?.policyRevision, 5);
    },
  );

  test(
    'header timeout retains a verified gate and aborts the request',
    () async {
      final store = _MemoryKeyValueStore();
      await _service(
        storage: store,
        httpClient: _QueueHttpClient([
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(minimumVersion: '2.0.0'),
          ),
        ]),
      ).checkForUpdates(force: true);
      final client = _PendingHttpClient();
      final service = _service(
        storage: store,
        httpClient: client,
        requestTimeout: const Duration(milliseconds: 30),
      );
      final task = service.checkForUpdates(force: true);
      await client.started(1);
      final result = await task;
      expect(result.versionUnsupported, isTrue);
      expect(result.usedCache, isTrue);
      expect(result.failureReason, contains('TimeoutException'));
      await expectLater(
        (client.requests.single as http.AbortableRequest).abortTrigger,
        completes,
      );
      client.complete(0, _manifestJson(policyRevision: 5));
    },
  );

  test('stream timeout releases the response subscription', () async {
    var cancelled = false;
    final body = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    final client = _PendingHttpClient();
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: client,
      requestTimeout: const Duration(milliseconds: 30),
    );
    final task = service.checkForUpdates(force: true);
    await client.started(1);
    client.pending.single.complete(http.StreamedResponse(body.stream, 200));
    await expectLater(task, throwsA(isA<TimeoutException>()));
    expect(cancelled, isTrue);
    await body.close();
  });

  test(
    'a response after timeout cannot overwrite the next verified policy',
    () async {
      final client = _PendingHttpClient();
      final service = _service(
        storage: _MemoryKeyValueStore(),
        httpClient: client,
        requestTimeout: const Duration(milliseconds: 30),
      );
      await expectLater(
        service.checkForUpdates(force: true),
        throwsA(isA<TimeoutException>()),
      );
      final current = service.checkForUpdates(force: true);
      await client.started(2);
      client.complete(
        1,
        _manifestJson(policyRevision: 5, minimumVersion: '2.0.0'),
      );
      expect((await current).versionUnsupported, isTrue);
      client.complete(
        0,
        _manifestJson(policyRevision: 4, minimumVersion: '1.0.0'),
      );
      await Future<void>.delayed(Duration.zero);
      final cached = await service.loadCachedUpdate();
      expect(cached.latestManifest?.policyRevision, 5);
      expect(cached.versionUnsupported, isTrue);
    },
  );

  test(
    'dispose aborts an adapter that ignores cancellation and prevents late cache writes',
    () async {
      final store = _MemoryKeyValueStore();
      final client = _PendingHttpClient();
      final service = _service(storage: store, httpClient: client);
      final task = service.checkForUpdates(force: true);
      await client.started(1);
      service.dispose();
      await expectLater(task, throwsA(isA<UpdateInstallFailed>()));
      client.complete(0, _manifestJson());
      await Future<void>.delayed(Duration.zero);
      expect(store.values, isEmpty);
    },
  );

  test(
    'confirmed absence remains absence across restart and offline checks',
    () async {
      final store = _MemoryKeyValueStore();
      final service = _service(
        storage: store,
        officialTenant: false,
        httpClient: _QueueHttpClient([
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(minimumVersion: '2.0.0'),
          ),
          _HttpFixture.text(
            'https://updates.example/latest.json',
            404,
            'missing',
          ),
        ]),
      );
      await service.checkForUpdates(force: true);
      await service.checkForUpdates(force: true);
      final restarted = _service(
        storage: store,
        officialTenant: false,
        httpClient: _QueueHttpClient([
          _HttpFixture.text(
            'https://updates.example/latest.json',
            503,
            'offline',
          ),
        ]),
      );
      expect((await restarted.loadCachedUpdate()).policyUnavailable, isTrue);
      final cached = await restarted.checkForUpdates(force: false);
      expect(cached.policyUnavailable, isTrue);
      expect(cached.latestManifest, isNull);
      final offline = await restarted.checkForUpdates(force: true);
      expect(offline.policyUnavailable, isTrue);
      expect(offline.versionUnsupported, isFalse);
      expect(offline.usedCache, isTrue);
    },
  );

  for (final wrongOrigin in [false, true]) {
    test(
      'disabled policy cannot clear a gate with ${wrongOrigin ? "another origin" : "an older revision"}',
      () async {
        final disabled = _serverInfoJson(
          origin: wrongOrigin
              ? 'https://wrong.example'
              : 'https://updates.example',
        );
        final releases = disabled['client_versions']! as Map<String, Object?>;
        releases['policy_revision'] = wrongOrigin ? 10 : 3;
        (releases['products']! as Map<String, Object?>)['app'] =
            <String, Object?>{'enabled': false};
        final service = _service(
          storage: _MemoryKeyValueStore(),
          httpClient: _QueueHttpClient([
            _HttpFixture.json(
              'https://updates.example/latest.json',
              _manifestJson(policyRevision: 9, minimumVersion: '2.0.0'),
            ),
            _HttpFixture.json('https://updates.example/latest.json', disabled),
          ]),
        );
        await service.checkForUpdates(force: true);
        final result = await service.checkForUpdates(force: true);
        expect(result.versionUnsupported, isTrue);
        expect(result.usedCache, isTrue);
        expect(result.failureReason, isNotNull);
      },
    );
  }

  test(
    'cache write failure does not discard a verified live restriction',
    () async {
      final service = _service(
        storage: _ReadOnlyStore(),
        httpClient: _QueueHttpClient([
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(minimumVersion: '2.0.0'),
          ),
          _HttpFixture.text(
            'https://updates.example/latest.json',
            503,
            'offline',
          ),
        ]),
      );
      expect(
        (await service.checkForUpdates(force: true)).versionUnsupported,
        isTrue,
      );
      expect(
        (await service.checkForUpdates(force: true)).versionUnsupported,
        isTrue,
      );
    },
  );

  test('legacy cached minimum is applied before its first refresh', () async {
    final store = _MemoryKeyValueStore();
    final seeded = _service(
      storage: store,
      httpClient: _QueueHttpClient([
        _HttpFixture.json(
          'https://updates.example/latest.json',
          _manifestJson(minimumVersion: '2.0.0'),
        ),
      ]),
    );
    await seeded.checkForUpdates(force: true);
    seeded.dispose();
    final key = store.values.keys.singleWhere(
      (key) => key.endsWith('_policy_v1'),
    );
    store.values.remove(key);
    store.values[key.replaceFirst(RegExp(r'_policy_v1$'), '_manifest')] =
        jsonEncode(_manifestJson(minimumVersion: '2.0.0'));
    final restarted = _service(
      storage: store,
      httpClient: _QueueHttpClient([]),
    );
    addTearDown(restarted.dispose);
    final cached = await restarted.loadCachedUpdate();
    expect(cached.versionUnsupported, isTrue);
    expect(cached.usedCache, isTrue);
  });

  test(
    'policy replacement survives failed auxiliary writes and restart',
    () async {
      final store = _FailCheckTimestampStore();
      final service = _service(
        storage: store,
        officialTenant: false,
        httpClient: _QueueHttpClient([
          _HttpFixture.text(
            'https://updates.example/latest.json',
            404,
            'missing',
          ),
          _HttpFixture.json(
            'https://updates.example/latest.json',
            _manifestJson(minimumVersion: '2.0.0'),
          ),
        ]),
      );
      expect(
        (await service.checkForUpdates(force: true)).policyUnavailable,
        isTrue,
      );
      expect(
        (await service.checkForUpdates(force: true)).versionUnsupported,
        isTrue,
      );
      service.dispose();
      final restarted = _service(
        storage: store,
        httpClient: _QueueHttpClient([]),
      );
      addTearDown(restarted.dispose);
      final cached = await restarted.loadCachedUpdate();
      expect(cached.versionUnsupported, isTrue);
      expect(cached.policyUnavailable, isFalse);
    },
  );

  test('dispose does not close an injected HTTP client', () async {
    final client = _QueueHttpClient(const <_HttpFixture>[]);
    final service = _service(
      storage: _MemoryKeyValueStore(),
      httpClient: client,
    );

    service.dispose();

    expect(client.isClosed, isFalse);
  });

  test(
    'disposed tenant cannot start an official check after preference I/O',
    () async {
      final store = _PendingPreferenceStore();
      final client = _PendingHttpClient();
      final service = _service(storage: store, httpClient: client);
      final check = service.checkOfficialSource(
        AppOfficialUpdateSource.secondary,
      );
      await store.started.future;
      service.dispose();
      store.finish.complete();
      await expectLater(check, throwsStateError);
      expect(client.requests, isEmpty);
    },
  );
}

AppUpdateService _service({
  required AppKeyValueStore storage,
  required http.Client httpClient,
  Future<bool> Function(Uri uri)? urlLauncher,
  String tenantId = 'tenant-test',
  bool officialTenant = true,
  Duration requestTimeout = const Duration(seconds: 15),
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
    tenantId: tenantId,
    backendBaseUrl: 'https://updates.example/backend',
    manifestUrl: 'https://updates.example/latest.json',
    releasesUrl: 'https://updates.example/releases',
    officialTenant: officialTenant,
    requestTimeout: requestTimeout,
  );
}

Map<String, Object?> _manifestJson({
  int buildNumber = 12,
  int policyRevision = 4,
  String minimumVersion = '1.0.0',
  String? macosAppcastUrl = 'https://updates.example/appcast.xml',
  String origin = 'https://updates.example',
}) {
  return <String, Object?>{
    'product': 'awiki-me',
    'channel': 'stable',
    'policy_origin': origin,
    'policy_revision': policyRevision,
    'version': '1.2.0',
    'buildNumber': buildNumber,
    'minimum_supported_version': minimumVersion,
    'minimum_supported_build_number': 1,
    'published_at': '2026-06-15T01:02:03.000Z',
    'release_notes_url': '$origin/releases/1.2.0',
    'publishedAt': '2026-06-15T01:02:03.000Z',
    'releaseNotesUrl': '$origin/releases/1.2.0',
    'githubReleaseUrl': '$origin/releases/1.2.0',
    'platforms': <String, Object?>{
      'macos': <String, Object?>{
        if (macosAppcastUrl != null) 'appcastUrl': macosAppcastUrl,
        'downloadUrl': '$origin/awiki-me.dmg',
        'sha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'sizeBytes': 123,
      },
      'android': <String, Object?>{
        'downloadUrl': '$origin/awiki-me.apk',
        'sha256':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'sizeBytes': 456,
      },
      'windows-x64': <String, Object?>{
        'downloadUrl': '$origin/awiki-me.exe',
        'sha256':
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        'sizeBytes': 789,
      },
    },
  };
}

Map<String, Object?> _serverInfoJson({
  String origin = 'https://updates.example',
  String minimumVersion = '1.0.0',
}) {
  Map<String, Object?> platform(String name) => <String, Object?>{
    'enabled': true,
    'download_page_url': '$origin/downloads/$name',
    'artifact': <String, Object?>{
      'url': '$origin/downloads/awiki-me.$name',
      'mirrors': <String>[],
      'sha256':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'size_bytes': 123,
    },
  };
  return <String, Object?>{
    'schema_version': 1,
    'client_versions': <String, Object?>{
      'schema_version': 1,
      'channel': 'stable',
      'policy_origin': origin,
      'policy_revision': 4,
      'published_at': '2026-06-15T01:02:03.000Z',
      'products': <String, Object?>{
        'app': <String, Object?>{
          'enabled': true,
          'recommended_version': '1.2.0',
          'recommended_build_number': 12,
          'minimum_supported_version': minimumVersion,
          'minimum_supported_build_number': 1,
          'minimum_release': '0903',
          'release_notes_url': '$origin/releases/1.2.0',
          'platforms': <String, Object?>{
            'android': platform('android'),
            'macos': platform('macos'),
            'windows': platform('windows'),
          },
        },
        'cli': <String, Object?>{'enabled': false},
        'dsh': <String, Object?>{'enabled': false},
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
  bool isClosed = false;

  @override
  void close() {
    isClosed = true;
    super.close();
  }

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

class _PendingHttpClient extends http.BaseClient {
  final pending = <Completer<http.StreamedResponse>>[];
  final requests = <http.BaseRequest>[];
  final changes = StreamController<int>.broadcast(sync: true);
  Future<void> started(int count) async {
    if (pending.length < count) {
      await changes.stream.firstWhere((value) => value >= count);
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    pending.add(Completer<http.StreamedResponse>());
    changes.add(pending.length);
    return pending.last.future;
  }

  void complete(int index, Map<String, Object?> value) {
    pending[index].complete(
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(value))), 200),
    );
  }
}

class _ReadOnlyStore extends _MemoryKeyValueStore {
  @override
  Future<void> write({required String key, required String value}) async =>
      throw StateError('read only');
}

class _FailCheckTimestampStore extends _MemoryKeyValueStore {
  @override
  Future<void> write({required String key, required String value}) async {
    if (key.endsWith('_checked_at')) throw StateError('timestamp write failed');
    await super.write(key: key, value: value);
  }
}

class _PendingPreferenceStore extends _MemoryKeyValueStore {
  final started = Completer<void>();
  final finish = Completer<void>();
  @override
  Future<void> write({required String key, required String value}) async {
    if (key.endsWith('_preferred_official_source')) {
      started.complete();
      await finish.future;
    }
    await super.write(key: key, value: value);
  }
}
