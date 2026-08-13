import 'dart:convert';
import 'dart:io';

import 'package:awiki_im_core/awiki_im_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android publishes the pre-OTP vault record before Handle Recovery sends',
    (_) async {
      final root = await Directory.systemTemp.createTemp(
        'awiki_android_handle_recovery_vault_',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      AwikiImCore? core;
      addTearDown(() async {
        await core?.dispose();
        await server.close(force: true);
        if (await root.exists()) await root.delete(recursive: true);
      });

      final vaultDir = Directory(p.join(root.path, 'identity-vault'));
      final requestObserved = server.first.then((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final recordsDir = Directory(p.join(vaultDir.path, 'records'));
        final entries = await recordsDir.list().toList();
        final records = entries
            .whereType<File>()
            .where((file) => p.extension(file.path) == '.json')
            .toList();
        final temporaryFiles = entries
            .whereType<File>()
            .where((file) => p.extension(file.path) == '.tmp')
            .toList();

        expect(request.uri.path, '/user-service/v1/handle/rpc');
        expect(body['method'], 'send_otp');
        expect(records, hasLength(1));
        expect(await records.single.length(), greaterThan(0));
        expect(temporaryFiles, isEmpty);

        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': body['id'],
            'result': <String, Object?>{
              'ok': true,
              'retry_after_seconds': 60,
              'retry_at': '2099-08-13T08:00:00Z',
            },
          }),
        );
        await request.response.close();
        return body;
      });

      core = await AwikiImCore.open(
        config: AwikiImCoreConfig(
          serviceBaseUrl: 'http://127.0.0.1:${server.port}',
          didDomain: 'awiki.test',
          transportPolicy: MessageTransportPolicy.httpOnly,
        ),
        paths: AwikiImCorePaths(
          identityRootDir: p.join(root.path, 'identities'),
          registryPath: p.join(root.path, 'identities', 'registry.json'),
          defaultIdentityPath: p.join(root.path, 'identities', 'default'),
          sqlitePath: p.join(root.path, 'local', 'im.sqlite'),
          cacheDir: p.join(root.path, 'cache'),
          tempDir: p.join(root.path, 'tmp'),
        ),
        openOptions: AwikiImCoreOpenOptions.vaultRequired(
          identitySecretVault: ImCoreSecretVaultOptions(
            rootKey: DeviceVaultRootKey.fromList(List<int>.filled(32, 81)),
            vaultDir: vaultDir.path,
            workspaceId: 'android-recovery-regression-workspace',
            deviceId: 'android-recovery-regression-device',
          ),
          multiDeviceHandleRecoveryEnabled: true,
          multiDeviceAudience: 'awiki-user-service',
        ),
      );

      final result = await core.requestHandleRecoveryOtp(
        fullHandle: 'alice.awiki.test',
        phone: '+8613800000000',
      );
      final observedRequest = await requestObserved;

      expect(result.accepted, isTrue);
      expect(result.retryAfterSeconds, 60);
      expect(
        (observedRequest['params'] as Map)['operation_id'],
        result.operationId,
      );
      final operations = await core.listHandleRecoveryOperations(
        IdentitySelector.id(result.ownerIdentityId),
      );
      expect(operations, hasLength(1));
      expect(operations.single.operationId, result.operationId);
      expect(
        operations.single.lifecycleClass,
        HandleRecoveryOperationLifecycle.preCommit,
      );
      expect(operations.single.commitAttempted, isFalse);
      expect(operations.single.keyState, HandleRecoveryKeyState.available);
    },
    skip: !Platform.isAndroid,
  );
}
